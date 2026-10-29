extends "res://tools/test_editor_native_texture_edges.gd"
## Headless publication/lifetime regression. Uses the real native texture class;
## only engine registration/path observations are controlled without a renderer.
const Ownership=preload("res://scripts/world_editor/prepared_model_ownership.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")

class NativePool extends ControlledPool:
	func _streamed_handoff_texture_valid(texture:Texture2D)->bool:
		return texture.get_script()==null and texture.is_class("StreamedTexture2D")
	func _load_stream(row:Dictionary,digest:String)->Texture2D:
		var texture:Texture2D=ClassDB.instantiate("StreamedTexture2D")
		texture.set_meta("runtime_source_sha256",digest)
		texture.set_meta("runtime_texture_representation",row.representation)
		texture.set_meta("ownership_cpu_load_path",row.path)
		return texture

class Tracker extends Ownership:
	var proofs:Array=[]
	func preflight(candidate:Dictionary,packet:Dictionary,envelope_bytes:int)->Dictionary:
		var receipt:=super.preflight(candidate,packet,envelope_bytes)
		if receipt.ok:
			var counts:Dictionary={}
			for field:String in ["graph_visits","split_texture_rows","split_binding_entries","split_slot_checks","split_binding_graph_checks"]:counts[field]=receipt.get(field,-1)
			proofs.append(counts)
		return receipt
	func _streamed_identity_valid(texture:Texture2D,row:Dictionary)->bool:
		return texture.get_script()==null and texture.is_class("StreamedTexture2D") and texture.get_meta("ownership_cpu_load_path","")==row.path

class ScopeProbe extends Resource:
	var ledger:RefCounted
	var catalog:WeakRef
	var index:int
	var observations:Dictionary
	func _notification(what:int)->void:
		if what!=NOTIFICATION_PREDELETE:return
		var owner:RefCounted=catalog.get_ref()
		observations[index]={"queue_bytes":ledger.reserved_bytes,"metadata_bytes":owner.native_metadata_reserved_bytes if owner!=null else -1,"main":Thread.is_main_thread()}

func fixture(name_:String,split:bool)->Dictionary:
	var model:=super.fixture(name_,split)
	# The general queue fixture uses a human-readable generator. The publisher
	# requires the production generator SHA, so preserve that stricter contract.
	var index:=Compiled.index_path(model.path,content_root)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(index))
	manifest.generator="c".repeat(64);write(index,JSON.stringify(manifest))
	var path:=Footprint.descriptor_path(model.path,content_root)
	var descriptor:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var footprint:Dictionary=JSON.parse_string(descriptor.body);footprint.generator=manifest.generator
	var body:=JSON.stringify(footprint)
	write(path,JSON.stringify({"version":1,"body":body,"sha256":body.sha256_text()}))
	return model

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):
		printerr("Requires isolated review_artifacts content root");quit(2);return
	create_timer(45.0).timeout.connect(func():printerr("SPLIT_OWNERSHIP watchdog");quit(2))
	var previous:=Job.prepared_model_residency_enabled
	Job.prepared_model_residency_enabled=true
	await publication_and_lifetime()
	await empty_table_publication()
	Job.prepared_model_residency_enabled=previous
	check(not Job.prepared_model_residency_enabled,"optional publisher remains disabled by default")
	print("EDITOR_SPLIT_NATIVE_OWNERSHIP checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func publication_and_lifetime()->void:
	var first:=fixture("ownership_first",true);var second:=fixture("ownership_second",true)
	var host:=Host.new();root.add_child(host);var pool:=NativePool.new()
	var job:=begin(host,[record(first),record(second)],pool)
	var tracker:=Tracker.new();root.add_child(tracker);tracker.set_process(false)
	job._model_ownership=tracker
	var queue:Node=job._preparation;var key:String="model:"+first.path
	var deadline:=Time.get_ticks_msec()+4000
	while not queue.is_ready(key) and Time.get_ticks_msec()<deadline:await process_frame
	check(queue.is_ready(key),"actual LoadJob reaches complete split native READY")
	var packet:Dictionary=queue.rows[key].packet
	var candidate:Dictionary=job._model_candidates[first.path]
	var charge:int=candidate.estimated_bytes
	preflight_boundaries(tracker,candidate,packet,queue)
	var held_metadata:=Image.new()
	packet.prefab_texture_packet.uploaded_textures.values()[0].set_meta("geometry_child",held_metadata)
	var scope:RefCounted=packet.native_texture_scope
	var helper:RefCounted=job._native_textures
	# Lifecycle instrumentation only: external mutation of these internal scalar
	# containers is unsupported. It must not require another table-validation pass.
	var lifetime:Dictionary=attach_scope_probes(scope,queue.ledger)
	var scope_probes:Array[WeakRef]=lifetime.probes
	var metadata_charge:int=helper.catalog.native_metadata_reserved_bytes
	check(metadata_charge>0 and queue.ledger.reserved_bytes>=charge,"live packet and borrowed table retain their existing budget coverage")
	var binding_alias:Dictionary=packet.native_texture_plan
	var pixel_alias:Dictionary=packet.prefab_texture_packet
	var proofs_before:int=tracker.proofs.size()
	var result:Dictionary=await job._prepare_asset(record(first))
	var scene:Node=result.get("scene")
	check(scene!=null,"experimental publisher accepts fully bound real StreamedTexture2D")
	check(packet.is_empty(),"publication clears the queue packet alias")
	if scene==null:
		print("OWNERSHIP_REJECTION ",JSON.stringify(job._timings.asset_lookahead.ownership_rejections))
		job._clear_asset_lookahead();job.free();host.free();tracker.free();return
	var texture:Texture2D=scene.get_child(0).mesh.surface_get_material(0).albedo_texture
	var texture_ref:WeakRef=weakref(texture)
	check(texture.is_class("StreamedTexture2D") and texture.get_script()==null,"bound texture uses the real engine class")
	check(tracker.report().published_envelope_bytes==charge,"publisher charges private geometry envelope")
	check(tracker.proofs.size()==proofs_before+1 and tracker.proofs.back().split_texture_rows==1 and tracker.proofs.back().split_binding_entries==1 and tracker.proofs.back().split_slot_checks==1,"actual first publication performs one proof over one texture/binding/slot")
	check(tracker.proofs.back().split_binding_graph_checks==1,"post-graph ownership proof checks only the one binding material")
	print("OWNERSHIP_PUBLICATION_VISITS ",JSON.stringify(tracker.proofs.back()))
	check(binding_alias.is_empty() and pixel_alias.is_empty(),"queue disposal clears nested binding and pixel packet aliases")
	check(scope.released and scope.prepared.is_empty() and scope.cached.is_empty() and scope.shared.is_empty() and scope.offered.is_empty() and not queue.rows[key].has("contract"),"scope and task aliases release before queue reservation ends")
	check(scope_probes[0].get_ref()==null and scope_probes[1].get_ref()==null,"shared and offer aliases do not retain controlled owners past queue release")
	check(lifetime.observations[0].queue_bytes>=charge and lifetime.observations[1].queue_bytes>=charge and lifetime.observations[0].main and lifetime.observations[1].main,"scope owner destructors observe their still-charged queue lease on main")
	check(scope_probes[2].get_ref()!=null and helper.catalog.native_metadata_reserved_bytes==metadata_charge,"borrowed table owner remains under the catalog metadata reservation")
	scope=null
	var second_result:Dictionary=await job._prepare_asset(record(second))
	var second_scene:Node=second_result.get("scene")
	check(second_scene!=null,"second model publishes through same experimental path")
	if second_scene!=null:
		check(second_scene.get_child(0).mesh.surface_get_material(0).albedo_texture==texture,"second model reuses the exact streamed owner")
	check(tracker.report().published_envelope_bytes==charge*2,"two published geometries retain two independent envelopes")
	texture.remove_meta("geometry_child")
	Drainer.dispose_scene(scene);scene=null;result.clear();Assets.evict_cached_scene(first.path)
	var retire_service:Node=root.get_node_or_null(Retirement.NODE_NAME)
	deadline=Time.get_ticks_msec()+4000
	while retire_service!=null and not retire_service.pending.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	tracker.collect_retired(100)
	check(tracker.report().published_envelope_bytes==charge*2,"escaped metadata child still retains the original geometry envelope")
	held_metadata=null
	deadline=Time.get_ticks_msec()+4000
	while Time.get_ticks_msec()<deadline:
		tracker.collect_retired(100)
		if tracker.report().published_envelope_bytes==charge:break
		await process_frame
	check(tracker.report().published_envelope_bytes==charge and second_scene!=null and texture!=null,"one geometry retires while another model still owns the shared streamed texture")
	if second_scene!=null:Drainer.dispose_scene(second_scene);second_scene=null
	second_result.clear();Assets.evict_cached_scene(second.path)
	job._clear_asset_lookahead()
	check(host._shared_preparation_ledger.reserved_bytes==0 and host._shared_preparation_ledger.count()==0,"queue work reservations drain exactly")
	check(scope_probes[2].get_ref()==null and helper.catalog.native_metadata_reserved_bytes==0,"last table pin releases the controlled owner before metadata credit is restored")
	check(lifetime.observations[2].metadata_bytes==metadata_charge and lifetime.observations[2].main,"table owner destructor observes the metadata charge before its deduction")
	deadline=Time.get_ticks_msec()+4000
	while Time.get_ticks_msec()<deadline:
		tracker.collect_retired(100)
		if tracker.report().published_envelope_bytes==0:break
		await process_frame
	check(tracker.report().published_envelope_bytes==0,"both geometry envelopes retire independently of held engine texture")
	texture=null
	check(texture_ref.get_ref()==null and pool.snapshot().outputs==0,"no scope or packet alias retains texture after final owners release")
	job.free();host.free();tracker.free()

func empty_table_publication()->void:
	var model:=variant("ownership_empty",true)
	var host:=Host.new();root.add_child(host);var pool:=NativePool.new()
	var job:=begin(host,[record(model)],pool)
	var tracker:Node=job._model_ownership
	var result:Dictionary=await job._prepare_asset(record(model))
	var scene:Node=result.get("scene")
	check(scene!=null,"default tracker publishes a complete empty split table without registration probes")
	check(tracker.report().entries==1,"empty table still owns one full geometry envelope")
	if scene!=null:Drainer.dispose_scene(scene);scene=null
	result.clear();Assets.evict_cached_scene(model.path);job._clear_asset_lookahead()
	var deadline:=Time.get_ticks_msec()+4000
	while tracker.report().entries>0 and Time.get_ticks_msec()<deadline:
		await process_frame;tracker.collect_retired(100)
	check(tracker.report().entries==0 and host._shared_preparation_ledger.reserved_bytes==0,"empty-table geometry and transient leases both retire")
	job.free();host.free()

func attach_scope_probes(scope:RefCounted,ledger:RefCounted)->Dictionary:
	# End this call before measuring release: a GDScript loop's temporary array
	# otherwise keeps the dictionaries alive in the test caller's stack frame.
	var probes:Array[WeakRef]=[]
	var observations:Dictionary={}
	for container:Dictionary in [scope.shared,scope.offered,scope.prepared]:
		var owned:=ScopeProbe.new();owned.ledger=ledger;owned.catalog=weakref(scope.catalog);owned.index=probes.size();owned.observations=observations
		probes.append(weakref(owned));container.lifetime_probe=owned
	return {"probes":probes,"observations":observations}

func preflight_boundaries(tracker:Node,candidate:Dictionary,packet:Dictionary,queue:Node)->void:
	var charge:int=candidate.estimated_bytes
	var ledger_before:Dictionary=queue.ledger.snapshot()
	var valid:Dictionary=tracker.preflight(candidate,packet,charge)
	check(valid.ok,"complete split preparation passes scoped preflight")
	check(queue.ledger.snapshot()==ledger_before and queue.ledger.reserved_bytes>=charge and tracker.report().published_envelope_bytes==0,"preflight projection keeps the full queue lease and has no published charge")
	check(not packet.is_read_only() and packet.has("native_texture_scope") and not packet.native_texture_plan.is_empty(),"preflight projection leaves mutable queue disposal packet intact")
	valid.clear()
	var strict:=Ownership.new();root.add_child(strict)
	var rejected:Dictionary=strict.preflight(candidate,packet,charge)
	check(not rejected.ok and rejected.reason=="split_texture_identity","default tracker rejects unregistered real StreamedTexture2D in headless")
	strict.free()
	for change:Dictionary in [{"unknown_owner":null},{"private_preparation":{}},{"native_waiting":true},{"native_texture_scope":RefCounted.new()}]:
		var bad:=packet.duplicate();bad.merge(change,true)
		check(not tracker.preflight(candidate,bad,charge).ok,"additional or incomplete ownership rejects: "+str(change.keys()[0]))
	for field:String in ["completed","owner","owners"]:
		var bad:=packet.duplicate();bad.native_texture_plan=packet.native_texture_plan.duplicate()
		bad.native_texture_plan[field]=false if field=="completed" else ({} if field=="owners" else Resource.new())
		check(not tracker.preflight(candidate,bad,charge).ok,"binding proof rejects invalid "+field)
	var bound:Dictionary=packet.native_texture_plan.bindings[0]
	var foreign:StandardMaterial3D=bound.material.duplicate()
	var bad_binding:=packet.duplicate();bad_binding.native_texture_plan=packet.native_texture_plan.duplicate()
	var foreign_entry:=bound.duplicate();foreign_entry.material=foreign
	bad_binding.native_texture_plan.bindings=[foreign_entry]
	check(not tracker.preflight(candidate,bad_binding,charge).ok,"a matching texture slot on a foreign material cannot escape graph ownership")
	for field:String in ["slots","targets"]:
		var malformed:=packet.duplicate();malformed.native_texture_plan=packet.native_texture_plan.duplicate()
		var malformed_entry:=bound.duplicate();malformed_entry[field]=[Resource.new()]
		malformed.native_texture_plan.bindings=[malformed_entry]
		check(not tracker.preflight(candidate,malformed,charge).ok,"binding descriptor rejects resource hidden in "+field)
	for field:String in ["keys","owners"]:
		var extra:=packet.duplicate();extra.native_texture_plan=packet.native_texture_plan.duplicate()
		extra.native_texture_plan[field]=packet.native_texture_plan[field].duplicate()
		extra.native_texture_plan[field][Resource.new()]=true if field=="keys" else Resource.new()
		check(not tracker.preflight(candidate,extra,charge).ok,"binding exact-set proof rejects additional "+field)
	var original:Texture2D=bound.material.get(bound.slots[0])
	for replacement:Texture2D in [null,ImageTexture.new()]:
		bound.material.set(bound.slots[0],replacement)
		check(not tracker.preflight(candidate,packet,charge).ok,"completed binding cannot publish a cleared or replaced material slot")
	bound.material.set(bound.slots[0],original);original=null
	for field:String in ["images","sources","profile"]:
		var bad:=packet.duplicate();bad.prefab_texture_packet=packet.prefab_texture_packet.duplicate()
		bad.prefab_texture_packet[field]={"unknown_owner":Resource.new()}
		check(not tracker.preflight(candidate,bad,charge).ok,"pixel packet cannot hide resource owner in "+field)
	var extra_pixels:=packet.duplicate();extra_pixels.prefab_texture_packet=packet.prefab_texture_packet.duplicate()
	extra_pixels.prefab_texture_packet.uploaded_textures=packet.prefab_texture_packet.uploaded_textures.duplicate()
	extra_pixels.prefab_texture_packet.uploaded_textures["unadmitted"]=Resource.new()
	check(not tracker.preflight(candidate,extra_pixels,charge).ok,"uploaded texture set cannot attach an extra resource")
	var bad_stages:=packet.duplicate();bad_stages.native_stages={"geometry_us":Resource.new()}
	check(not tracker.preflight(candidate,bad_stages,charge).ok,"stage metadata cannot own resources")
	var owners:Dictionary=packet.prefab_texture_packet.uploaded_textures
	var texture:Texture2D=owners.values()[0]
	var digest:String=texture.get_meta("runtime_source_sha256")
	texture.set_meta("runtime_source_sha256","d".repeat(64))
	check(not tracker.preflight(candidate,packet,charge).ok,"texture source SHA must match prior admitted source identity")
	texture.set_meta("runtime_source_sha256",digest)
	texture.set_meta("unexpected_owner",Resource.new())
	check(not tracker.preflight(candidate,packet,charge).ok,"engine-managed texture metadata still rejects unknown owner")
	texture.remove_meta("unexpected_owner")
	texture.set_meta("self_owner",texture)
	check(tracker.preflight(candidate,packet,charge).ok,"streamed owner is marked seen before cyclic metadata traversal")
	texture.remove_meta("self_owner")
	var scope:RefCounted=packet.native_texture_scope
	var binding_key:String=scope.pool._consumers[scope.consumer].values()[0]
	var entry:Dictionary=scope.pool._entries[binding_key]
	entry.streamed_handoff=false
	check(not tracker.preflight(candidate,packet,charge).ok,"native class alone cannot replace completed engine handoff receipt")
	entry.streamed_handoff=true
	var cached_scope:=Native.Scope.new();var cached_pool:=Shared.new()
	cached_scope.candidate=scope.candidate;cached_scope.prepared=scope.prepared
	cached_scope.catalog=scope.catalog;cached_scope.pool=cached_pool;cached_scope.committed=true;cached_scope.consumer="cached_cpu_probe"
	cached_scope.offered={"rows":scope.prepared.plan.rows}
	cached_scope.shared={"pool":cached_pool,"consumer":cached_scope.consumer,"leaders":{},"cached":{}}
	var texture_key:String=owners.keys()[0]
	cached_scope.cached={texture_key:{"texture":texture,"source_sha":digest}}
	cached_scope.cached_digests={texture_key:digest}
	cached_pool.commit(cached_scope.consumer,{"bindings":{},"leaders":{},"retained":{},"rows":{}})
	var cached_packet:=packet.duplicate();cached_packet.native_texture_scope=cached_scope
	check(tracker.preflight(candidate,cached_packet,charge).ok,"exact existing native ticket reuses its observed source identity without a new pool output")
	cached_scope.cached[texture_key].source_sha="e".repeat(64)
	check(not tracker.preflight(candidate,cached_packet,charge).ok,"cached native ticket cannot change its existing source identity")
	cached_scope.cached[texture_key].source_sha=digest
	cached_scope.cached[texture_key].unknown_owner=Resource.new()
	check(not tracker.preflight(candidate,cached_packet,charge).ok,"cached ticket cannot attach an arbitrary additional owner")
	cached_packet.clear();cached_pool.release(cached_scope.consumer)
	check(queue.ledger.snapshot()==ledger_before and tracker.report().entries==0,"all rejected preflights preserve queue accounting and published ownership")
