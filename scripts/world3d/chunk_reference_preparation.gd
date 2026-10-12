extends RefCounted
## Worker-only CPU transaction for a demanded reference set. No Node, Mesh,
## texture upload, GPU import, or shared scene-library mutation occurs here.
const Index = preload("res://scripts/world3d/map_dependency_index.gd")
const Store = preload("res://scripts/world3d/map_resource_store.gd")
const Cursor = preload("res://scripts/world3d/document_open_cursor.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Prefab = preload("res://scripts/world3d/house_prefab.gd")
const PrefabTextures = preload("res://scripts/world3d/prefab_texture_preparation.gd")
const RoadPreparation = preload("res://scripts/world3d/native_road_preparation.gd")
const OwnershipProof = preload("res://scripts/world3d/dependency_index_proof.gd")
const CollisionProducts=preload("res://scripts/world3d/collision_product_cache.gd")

static func _fail(reason: String, cancelled: bool = false, failed_uuid: String = "") -> Dictionary:
	return {"error": reason, "cancelled": cancelled, "failed_uuid": failed_uuid, "records": [], "dependencies": {}, "surface_arrays": {}, "read_profile": {}}

static func _cancelled(token: RefCounted) -> bool:
	return token != null and token.is_cancelled()

static func prepare(index: Dictionary, requested_entries: Array, path: String, content_root: String, token: RefCounted = null, ownership_proof: OwnershipProof = null, texture_plan: Dictionary = {}, shared_pixels:Dictionary={},collision_workspace:int=0) -> Dictionary:
	var started := Time.get_ticks_usec()
	if _cancelled(token): return _fail("区块引用准备已取消", true)
	if not Paths.allowed(path, content_root) or not index.get("ok", false) or not Store._digest(index.get("source_sha256")): return _fail("无效的区块引用来源")
	if requested_entries.is_empty() or requested_entries.size() > Store.MAX_RECORDS: return _fail("无效的区块引用请求数量")
	if FileAccess.get_sha256(path) != index.source_sha256: return _fail("地图来源在区块准备前已改变")
	var ownership_started := Time.get_ticks_usec()
	if not Index.validate_index_ownership(index, content_root, ownership_proof, path): return _fail("无效的完整建筑归属目录")
	var preflight_ownership_us := Time.get_ticks_usec() - ownership_started
	var requested := {}; var compact: Array = []; var dependencies := {}; var positions: Array = []
	for entry in requested_entries:
		if not entry is Dictionary or not entry.get("record_index") is int: return _fail("无效的区块引用条目")
		var at: int = entry.record_index
		if at < 0 or at >= index.rows.size() or requested.has(at): return _fail("区块引用顺序或身份无效")
		var row: Dictionary = index.rows[at]; var source: Dictionary = index.extras.rmmo_records[at]
		if entry.get("compact_record") != source or entry.get("group_id", "") != row.group_id or entry.get("asset_path", "") != row.asset_path: return _fail("区块引用与原始目录不一致")
		var expected: AABB = index.groups[row.group_id].bounds if not row.group_id.is_empty() else row.bounds
		if not entry.get("bounds") is AABB or entry.bounds != expected: return _fail("区块请求边界与目录不一致")
		requested[at] = true; positions.append(at)
	# Demand never splits a building or a fortification fixture namespace. Reject before touching any rmres file.
	for at in positions:
		var group_id: String = index.rows[at].group_id
		if not group_id.is_empty():
			for member in index.groups[group_id].members:
				if not requested.has(member): return _fail("区块请求缺少同一原子组的组件")
	positions.sort()
	for at in positions:
		var source: Dictionary = index.extras.rmmo_records[at]
		compact.append(source); dependencies[source.rmmo_ref.uri] = source.rmmo_ref.sha256
	if _cancelled(token): return _fail("区块引用准备已取消", true)
	var preflight_us := Time.get_ticks_usec() - started
	# The outer demand scheduler owns concurrency and byte admission. A single
	# task must not multiply that limit with another four-thread nested pool.
	var restored: Dictionary = Store.read_records(compact, path, content_root, dependencies, 1)
	if not restored.get("ok", false):
		# This task uses one resource reader, so its last claimed unique URI is
		# the failed dependency. Attribute it without poisoning a shared GLB path.
		var failed_uuid := ""
		var at := int(restored.get("read_profile",{}).get("reads_started",0)) - 1
		var uris: Array = dependencies.keys()
		if at >= 0 and at < uris.size():
			for record: Dictionary in compact:
				if record.rmmo_ref.uri == uris[at]: failed_uuid = record.uuid; break
		return _fail(str(restored.get("reason", "区块引用资源无法读取")), false, failed_uuid)
	if _cancelled(token): return _fail("区块引用准备已取消", true)
	var material_checks := {}; var asset_paths := {}; var ids := {}; var manifests := {}; var recomputed: Array = []
	var validation_started := Time.get_ticks_usec(); var prefabs := 0; var prefab_cpu := {}; var texture_sources := {}
	var roads: Array = []
	var collision_candidates:Dictionary={};var collision_metrics:Dictionary={"hits":0,"misses":0,"writes":0,"write_skips":0,"bytes":0,"workspace_bytes":collision_workspace}
	for i in restored.records.size():
		if _cancelled(token): return _fail("区块引用准备已取消", true)
		var record: Dictionary = restored.records[i]; var at: int = positions[i]; var expected: Dictionary = index.rows[at]
		var issue: String = Cursor.asset_record_issue(record, material_checks, compact[i].rmmo_ref.sha256, asset_paths, content_root)
		if issue.is_empty(): issue = Cursor.document_record_issue(record, ids)
		if issue.is_empty() and not preload("res://scripts/world3d/river_material_data.gd").valid(record): issue = "Invalid river material record"
		if not issue.is_empty(): return _fail(issue, false, record.uuid)
		if record.has("road_mesh"):
			var estimate := RoadPreparation.estimate(record)
			if not estimate.ok: return _fail(str(estimate.reason), false, record.uuid)
			if int(expected.get("memory_bytes", 0)) < int(estimate.estimated_bytes): return _fail("道路派生数组超出区块目录的内存预算", false, record.uuid)
			roads.append(record)
		if record.has("house_prefab"):
			var key:String=record.house_prefab.sha256
			if not prefab_cpu.has(key):
				var cached_faces:Dictionary={};var collision_identity:Dictionary={};var source_id:=-1
				if collision_workspace>=CollisionProducts.WORKSPACE_BYTES:
					source_id=Prefab.source_slot(record.house_prefab)
					if source_id>=0:
						var ref:Dictionary=compact[i].rmmo_ref
						var location:=Store._location(ref.uri,ref.sha256,path,content_root)
						collision_identity=CollisionProducts.identity({location:ref.sha256},"frozen:"+key+"/source:"+str(source_id),content_root)
						if not collision_identity.is_empty():
							var candidate:=CollisionProducts.read_candidate(collision_identity,content_root,token)
							if candidate.get("ok",false) and candidate.kind=="faces":cached_faces[source_id]=candidate;collision_metrics.hits+=1
							else:collision_metrics.misses+=1
				prefab_cpu[key]=Prefab.prepare_cpu(record,cached_faces)
				if not collision_identity.is_empty() and not prefab_cpu[key].is_empty():
					var candidate:Dictionary=cached_faces.get(source_id,{})
					if candidate.is_empty():
						candidate=CollisionProducts.make_candidate(collision_identity,prefab_cpu[key].collision_faces[source_id])
						if candidate.get("ok",false):
							var stored:=CollisionProducts._store_bound_candidate(candidate,content_root,collision_workspace,token)
							collision_metrics["writes" if stored.ok else "write_skips"]+=1
					if candidate.get("ok",false):collision_candidates[key]={source_id:candidate};collision_metrics.bytes+=int(candidate.bytes)
			if prefab_cpu[key].is_empty(): return _fail("无效的区块预制件数据", false, record.uuid)
			prefabs += 1
		if not texture_plan.is_empty():
			var actual_textures:=PrefabTextures.sources(record)
			if actual_textures!=expected.get("prefab_textures",{}):return _fail("预制件贴图依赖与目录不一致",false,record.uuid)
			texture_sources.merge(actual_textures,true)
		# Recompute actual geometry-derived bounds from the verified definition.
		# The index/request hint cannot grant safety to a smaller invented box.
		var actual: Dictionary = Index._classify(record, content_root, manifests)
		if expected.bounds_known and (not actual.bounds_known or not actual.bounds.is_equal_approx(expected.bounds)): return _fail("实际物件边界与区块目录不一致", false, record.uuid)
		if actual.owner_keys != expected.owner_keys: return _fail("实际物件归属与区块目录不一致", false, record.uuid)
		if expected.reason in ["native_fortification", "native_bridge"] and actual.reason != expected.reason: return _fail("冻结结构不能证明为自包含组件", false, record.uuid)
		if not expected.group_id.is_empty() and not expected.bounds_known: return _fail("未知边界建筑必须沿完整加载路径准备")
		actual.order = at; actual.group_id = expected.group_id
		recomputed.append(actual)
	var actual_groups: Dictionary = Index._groups(recomputed)
	for group_id: String in actual_groups:
		var actual: Dictionary = actual_groups[group_id]; var expected: Dictionary = index.groups[group_id]
		if actual.members != expected.members or actual.bounds_known != expected.bounds_known or (expected.bounds_known and not actual.bounds.is_equal_approx(expected.bounds)): return _fail("实际完整组件组边界与区块目录不一致")
	var ownership: Dictionary = Index.validate_selected(index, restored.records, content_root, ownership_proof)
	if not ownership.ok: return _fail(str(ownership.reason))
	if _cancelled(token): return _fail("区块引用准备已取消", true)
	var validation_us := Time.get_ticks_usec() - validation_started
	var surface_arrays := {}; var road_array_us := 0; var road_array_bytes := 0; var road_estimated_bytes := 0
	for record: Dictionary in roads:
		var road := RoadPreparation.prepare(record, token)
		if not road.error.is_empty(): return _fail(str(road.error), bool(road.cancelled), str(record.uuid))
		surface_arrays[record.uuid] = road.arrays
		road_array_us += int(road.elapsed_us); road_array_bytes += int(road.output_bytes); road_estimated_bytes += int(road.estimated_bytes)
	var texture_packet:Dictionary={}
	if not texture_plan.is_empty():
		texture_packet=PrefabTextures.prepare(texture_sources,texture_plan,content_root,token,false,shared_pixels)
		if not texture_packet.error.is_empty():
			var failure:=_fail(texture_packet.error,texture_packet.cancelled)
			if texture_packet.get("retry_pixels",false):failure.retry_pixels=true;failure.source_revisions=texture_packet.get("source_revisions",{})
			return failure
	var verify_started := Time.get_ticks_usec()
	if not Store.verify_dependencies(dependencies, path, content_root, 1) or not Paths.allowed(path, content_root) or FileAccess.get_sha256(path) != index.source_sha256: return _fail("地图或区块引用资源在准备期间发生改变")
	if _cancelled(token): return _fail("区块引用准备已取消", true)
	if not texture_packet.is_empty() and not PrefabTextures.verify(texture_packet,content_root,token):return _fail("预制件贴图在区块准备结束前发生改变",_cancelled(token))
	# Only this successful existing final transaction grants the typed handoff.
	# Stream never reads disk or accepts a source_unverified Dictionary.
	var verified_sources:Dictionary={}
	if not collision_candidates.is_empty():
		for uri:String in dependencies:
			var location:=Store._location(uri,dependencies[uri],path,content_root)
			if not location.is_empty():verified_sources[location]=dependencies[uri]
	for key:String in collision_candidates:
		prefab_cpu[key].collision_products={}
		for source_id:int in collision_candidates[key]:
			var product:=CollisionProducts._seal_after_reference_validation(collision_candidates[key][source_id],verified_sources)
			if product==null:return _fail("Collision product source handoff mismatch")
			prefab_cpu[key].collision_products[source_id]=product
	var profile: Dictionary = restored.get("read_profile", {}).duplicate()
	profile.preflight_us = preflight_us; profile.preflight_ownership_us = preflight_ownership_us
	profile.selected_ownership_us = int(ownership.get("ownership_validation_us", 0)); profile.selected_uuid_lookup_us = int(ownership.get("uuid_lookup_us", 0))
	profile.ownership_proof_used = ownership.get("ownership_proof_used", false)
	profile.validation_us = validation_us; profile.final_verification_us = Time.get_ticks_usec() - verify_started
	profile.elapsed_us = Time.get_ticks_usec() - started; profile.prefab_instances = prefabs; profile.record_count = restored.records.size()
	profile.road_instances = roads.size(); profile.road_array_prepare_us = road_array_us; profile.road_array_upper_bytes = road_array_bytes; profile.road_estimated_bytes = road_estimated_bytes
	profile.prefab_textures=texture_packet.get("profile",{})
	profile.collision_products=collision_metrics
	return {"error": "", "cancelled": false, "records": restored.records, "record_indices": positions, "dependencies": dependencies, "prefab_cpu":prefab_cpu, "prefab_texture_packet":texture_packet, "waiting_pixels":texture_packet.get("waiting_pixels",false), "surface_arrays":surface_arrays, "read_profile": profile, "selected_closure_verified": true, "closure_complete": false}
