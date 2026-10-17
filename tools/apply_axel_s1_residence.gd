extends "res://tools/apply_axel_reference_layout.gd"
## S1 assembly uses native house deletion, independent assets and road graph edits.
const HOUSE="building_061ac981f7e8922e09fa"
const Imported=preload("res://scripts/world3d/imported_building.gd")
var entry_snapshot:Dictionary={}
var permitted:Dictionary={}
func before_placements(recipe:Dictionary)->void:
	report.scope="S1 bridge-left gable residence, closed courtyard and aligned entrance; inherited bank and vegetation layout"
	report.scene_id="s1_bridge"
	check(FileAccess.get_sha256(recipe.root_source.path)==recipe.root_source.sha256,"exact unchanged formal root for composed S1 transaction")
	check(FileAccess.get_sha256(recipe.asset_review.path)==recipe.asset_review.sha256,"exact reviewed house art handoff")
	check(FileAccess.get_sha256(recipe.stairs_review.path)==recipe.stairs_review.sha256,"exact reviewed five-step art handoff")
	if failed:return
	entry_snapshot=Doc.open_file(recipe.root_source.path).recovery_snapshot()
	report.root_source_sha256=recipe.root_source.sha256
	report.terrain_samples=[]
	for point:Array in recipe.get("terrain_samples",[]):
		var sampled:=await operation("sample_terrain_height",{"id":"axel_terrain_05_04","point":point})
		report.terrain_samples.append(sampled)
		if failed:return
	for field:String in ["changed_records","deleted_records","new_records"]:
		for id:String in report.get(field,[]):permitted[id]=true
	check(editor._doc.map_meta.building_instances.has(HOUSE),"expected old S1 generic house")
	if failed:return
	for id:String in editor._doc.map_meta.building_instances[HOUSE].parts.values():permitted[id]=true
	await operation("delete_building",{"id":HOUSE})
	if failed:return
	for row:Dictionary in recipe.get("pre_moves",[]):
		await operation("set_object_transform",{"id":row.id,"rotation":row.rotation,"size":row.scale})
		var record:Dictionary=editor._doc._find(row.id);var box:AABB=Foot.record_shape(record).bounds
		var point:=City.vec(row.point)
		if row.get("grounded",true):point.y=Props.ground(editor._doc,point)-.02
		var at:=City.vec(record.position)+point-Vector3(box.get_center().x,box.position.y,box.get_center().z)
		await operation("set_object_transform",{"id":row.id,"position":City.xyz(at)})
		permitted[row.id]=true
		report.placements=report.placements.filter(func(prior):return prior.id!=row.id)
		report.placements.append({"key":row.key,"id":row.id,"position":City.xyz(at),"scale":record.size})
		if failed:return
	var layout:=await operation("get_city_layout",{})
	var roads:Dictionary=recipe.road_request.duplicate(true);roads.expected_token=layout.road_token
	for node:Dictionary in roads.get("nodes",[]):
		if node.id in recipe.get("ground_road_nodes",[]):node.position[1]=Props.ground(editor._doc,City.vec(node.position))
	await operation("update_road_graph",roads)
func after_placements(recipe:Dictionary)->void:
	var doc=editor._doc;var house:Dictionary={}
	for row:Dictionary in report.placements:
		permitted[row.id]=true
		if row.key=="s1/hero_residence":house=doc._find(row.id)
	check(house.has("model_building") and Imported.verify_source(house),"S1 residence retains formal imported building identity")
	if failed:return
	report.house_components=await operation("list_building_components",{"id":house.uuid})
	var road_result:Dictionary=editor._roads.prepare({})
	check(road_result.get("ok",false),"native final roads and entrance clearance")
	report.road_validation={"ok":road_result.get("ok",false),"error":road_result.get("error",""),"conflicts":road_result.get("conflicts",[])}
	if failed:return
	# Check complete tree crowns against exterior building volumes, without
	# rerunning already accepted component-house interior tests.
	report.tree_clearance=[]
	for id:String in ["obj_791","obj_838","obj_839"]:
		var tree:Dictionary=doc._find(id);var conflicts:Array=[]
		for record:Dictionary in doc.records:
			if not record.has("building") and not record.has("model_building"):continue
			if Foot.batches_overlap(Foot.record_shapes(tree),Foot.record_shapes(record)):conflicts.append(record.uuid)
		check(conflicts.is_empty(),"entire tree crown clears building envelopes "+id)
		report.tree_clearance.append({"id":id,"conflicts":conflicts})
	var bank:Dictionary=doc._find("s1_reference_north_rock_bank")
	var bank_data=preload("res://scripts/world3d/rock_bank_mesh.gd")
	check(bank_data.valid(bank),"native bank retains editable parameters and closed mesh recipe")
	var surfaces:Array=[]
	for arrays:Array in bank_data.arrays(bank):
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		surfaces.append({"vertices":vertices.size(),"triangles":indices.size()/3,"normals":arrays[Mesh.ARRAY_NORMAL].size(),"uvs":arrays[Mesh.ARRAY_TEX_UV].size(),"tangents":arrays[Mesh.ARRAY_TANGENT].size()/4})
	report.bank_review={"record_sha256":City.token(bank),"generator_sha256":FileAccess.get_sha256("res://scripts/world3d/rock_bank_mesh.gd"),"surfaces":surfaces,"materials":bank.rock_bank_materials,"collision":bank.collision,"lod":"short native bank; no forced simplification; existing shared static landscape batching contract"}
	for row:Dictionary in doc.map_meta.town_reference.house_layout.placements:
		if row.get("id","")!="s1_north_courtyard":continue
		row.previous_building_id=HOUSE
		for key:String in ["building_id","parameters","component_ids","template_id","terrain_range"]:row.erase(key)
		row.object_id=house.uuid;row.position=house.position;row.rotation=house.rotation;row.yaw=house.rotation[1]
		row.entrance=recipe.entrance;row.component_ids=[house.uuid]
		row.label="石桥左侧高山墙住宅与闭合庭院"
		row.reference_stage="S1 dedicated gable residence; scene alignment under outdoor review"
	report.changed_records=[];report.deleted_records=[];report.new_records=[]
	var old_ids:Dictionary={}
	for old:Dictionary in entry_snapshot.records:
		old_ids[old.uuid]=true;var now:Dictionary=doc._find(old.uuid)
		if City.token(old)==City.token(now):continue
		check(permitted.has(old.uuid) or old.has("road_mesh"),"change limited to scoped S1 instances or native roads "+str(old.uuid))
		if now.is_empty():report.deleted_records.append(old.uuid)
		else:report.changed_records.append(old.uuid)
	for row:Dictionary in doc.records:
		if old_ids.has(row.uuid):continue
		check(permitted.has(row.uuid) or row.has("road_mesh"),"new record belongs to scoped S1 authoring "+str(row.uuid));report.new_records.append(row.uuid)
	var old_meta:Dictionary=entry_snapshot.map_meta.duplicate(true);var new_meta:Dictionary=doc.map_meta.duplicate(true)
	old_meta.building_instances.erase(HOUSE)
	for meta:Dictionary in [old_meta,new_meta]:
		meta.editor_layout.erase("roads");meta.editor_layout.erase("road_surface")
		meta.town_reference.house_layout.placements=meta.town_reference.house_layout.placements.filter(func(r):return r.get("id","")!="s1_north_courtyard")
	check(City.token(old_meta)==City.token(new_meta),"other reference shots, houses, terrain, water and birth remain identical")
