extends "res://tools/test_native_texture_cross_operation.gd"
## Real MapLoader start/process/exit; only external input and final construction
## are substituted. CPU owners deliberately bypass native RID validation.
class Map extends Loader:
	var fixture:Object
	var paths:Array=[]
	var completed:=false
	var observed_error:=OK
	var observed_message:String
	func _parse()->void:
		_content_root=fixture.content_root
		var result:Dictionary=_model_preparation.run(paths,Callable(),2,Callable(),_content_root)
		_native_texture_scope=result.get("native_texture_scope")
		_profile.native_texture_preparation=result.get("native_texture_profile",{})
		for entry:Dictionary in result.entries:_asset_states[entry.path]=entry
		_error=result.error;observed_error=_error;observed_message=result.get("error_message","");_record_meta={"fixture":true}
	func _start_entry_prefetch()->void:pass
	func _build_records()->void:completed=true;set_process(false)
	func _finish_error(_message:String)->void:completed=true;set_process(false)

func lookup(key:String,row:Dictionary)->Dictionary:
	return Prefab._texture_ticket(Paint.retained_texture(key),row)

func configure(map:Map,fixture:Object,model:PackedScene)->Pool:
	map.fixture=fixture
	var pool:=Pool.new();var prep:RefCounted=map._model_preparation
	prep.native_texture_pool=pool;prep.native_texture_preparer=fixture.fake_pixels
	prep.memory_estimator=func(_path:String)->Dictionary:return {"estimated_bytes":4096,"exclusive":false}
	prep.candidate_provider=func(_path:String)->Dictionary:return fixture.candidate
	prep.candidate_reader=func(_path:String,_candidate:Dictionary)->Dictionary:return {"error":OK,"compiled":true,"packed":model,"source_digest":fixture.candidate.source_sha}
	for property:Dictionary in map.get_property_list():
		if property.name=="_native_resident_bridge":map.get("_native_resident_bridge").lookup_override=lookup
	return pool

func run()->void:
	Paint.refresh_sources()
	var fixture:=Fixture.new();fixture.make_fixture()
	var blank:PackedScene=fixture.packed.duplicate(true)
	var old:=Map.new();var old_pool:=configure(old,fixture,fixture.packed)
	old.paths=[fixture.content_root.path_join("old.glb")];root.add_child(old);old.start("private-fixture")
	var deadline:=Time.get_ticks_msec()+10000
	while not old.completed and Time.get_ticks_msec()<deadline:await process_frame
	check(old.completed and old.observed_error==OK,"real MapLoader completes old initial operation")
	check(Assets.cache_packed(old.paths[0],old._asset_states[old.paths[0]].packed,fixture.candidate.source_sha),"old actual cache owns initial texture")
	var first:=identity(Assets._scenes[old.paths[0]]);var old_path:String=old.paths[0]
	old.free();fixture.packed=null;fixture.material=null
	check(old_pool.snapshot().consumers==0 and first.weak.get_ref()!=null,"old MapLoader exit retires scope while scene survives")
	var fresh:=Map.new();var pool:=configure(fresh,fixture,blank)
	fresh.paths=[fixture.content_root.path_join("new.glb")];root.add_child(fresh);fresh.start("private-fixture")
	deadline=Time.get_ticks_msec()+10000
	while not fresh.completed and Time.get_ticks_msec()<deadline:await process_frame
	check(fresh.completed and fresh.observed_error==OK,"fresh MapLoader finishes without waiting on its own main loop")
	check(pool.snapshot().produced==0 and pool.snapshot().get("streamed_loads",0)==0,"fresh Initial reuses old native texture without another producer")
	if fresh._asset_states.has(fresh.paths[0]):check(identity(fresh._asset_states[fresh.paths[0]].packed).id==first.id,"fresh Initial binds exact old texture owner")
	else:check(false,"fresh Initial retains a complete model")
	var bridge_profile:Dictionary=fresh._profile.native_texture_preparation.get("resident_bridge",{})
	check(bridge_profile.get("lookups",-1)==1 and bridge_profile.get("hits",0)==1,"main looks up only the one requested native key")
	check(fresh._profile.native_texture_preparation.get("resident_metadata_reserved_at_return",0)>0,"resident reply metadata remains charged through main consumption")
	fresh.free()
	await mixed_case(fixture,blank,first.id)
	await tight_tables_case(fixture,blank)
	await cancellation_case(fixture,blank)
	bridge_protocol_case(fixture)
	blank=null;fixture.free();Assets.evict_cached_scene(old_path)
	deadline=Time.get_ticks_msec()+2000
	while first.weak.get_ref()!=null and Time.get_ticks_msec()<deadline:await process_frame
	check(first.weak.get_ref()==null and pool.admission.count()==0,"MapLoader teardown returns owners and admission to zero")
	print("INITIAL_NATIVE_RESIDENT_BRIDGE ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)

func mixed_case(fixture:Object,blank:PackedScene,expected:int)->void:
	var metadata:Dictionary=fixture.candidate.duplicate(true)
	var table_path:String=fixture.content_root.path_join("cache/world3d/compiled_assets_v1/texture_tables_v1/"+metadata.texture_table.sha256+".json")
	var table:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(table_path));var id:String="c".repeat(64)
	var added:Dictionary=table.textures[InitialFixture.ID].duplicate(true);added.file="cache/world3d/model_textures_v1/"+id+".stex";added.pixel_sha=id
	table.textures[id]=added;table.image_bytes=128
	var encoded:=JSON.stringify(table);metadata.texture_table={"version":1,"sha256":encoded.sha256_text(),"bytes":encoded.to_utf8_buffer().size(),"textures":2,"image_bytes":128}
	var file:=FileAccess.open(table_path.get_base_dir().path_join(metadata.texture_table.sha256+".json"),FileAccess.WRITE);file.store_string(encoded);file.close()
	var scene:=blank.instantiate();scene.set_meta(InitialFixture.Binding.TABLE_META,metadata.texture_table.sha256)
	var material:StandardMaterial3D=scene.get_child(0).mesh.surface_get_material(0).duplicate(false)
	material.normal_enabled=true
	var bindings:Dictionary=material.get_meta(InitialFixture.Binding.BINDINGS_META).duplicate(true);bindings["normal_texture"]={"id":id,"normal":true};material.set_meta(InitialFixture.Binding.BINDINGS_META,bindings)
	scene.get_child(0).mesh=scene.get_child(0).mesh.duplicate(false);scene.get_child(0).mesh.surface_set_material(0,material)
	var mixed:=PackedScene.new();mixed.pack(scene);scene.free()
	var map:=Map.new();var pool:=configure(map,fixture,mixed)
	map._model_preparation.candidate_provider=func(_path:String)->Dictionary:return metadata
	map.paths=[fixture.content_root.path_join("mixed.glb")];root.add_child(map);map.start("private-fixture")
	var deadline:=Time.get_ticks_msec()+5000
	while not map.completed and Time.get_ticks_msec()<deadline:await process_frame
	check(map.completed and map.observed_error==OK,"mixed cached/new Initial completes through real MapLoader")
	print("MIXED_RESULT ",JSON.stringify({"error":map.observed_error,"message":map.observed_message,"profile":map._profile.get("native_texture_preparation",{})}))
	check(pool.snapshot().produced==1 and pool.snapshot().streamed_loads==1,"only the one missing product creates a producer")
	check(pool.snapshot().handoff_outputs==1 and pool.snapshot().handoff_full_chain_bytes==128,"mixed handoff transfers only the new product reservation")
	check(material.albedo_texture.get_instance_id()==expected and material.normal_texture!=null and material.normal_texture!=material.albedo_texture,"mixed binding preserves old owner and includes the new texture")
	map.free();material=null;mixed=null
	check(pool.admission.count()==0 and pool.snapshot().outputs==0,"mixed output retirement empties admission and pool")

func tight_tables_case(fixture:Object,blank:PackedScene)->void:
	var other:Dictionary=fixture.candidate.duplicate(true)
	var table_path:String=fixture.content_root.path_join("cache/world3d/compiled_assets_v1/texture_tables_v1/"+other.texture_table.sha256+".json")
	var encoded:=FileAccess.get_file_as_string(table_path)+" "
	other.texture_table.sha256=encoded.sha256_text();other.texture_table.bytes=encoded.to_utf8_buffer().size()
	var file:=FileAccess.open(table_path.get_base_dir().path_join(other.texture_table.sha256+".json"),FileAccess.WRITE);file.store_string(encoded);file.close()
	var node:=blank.instantiate();node.set_meta(InitialFixture.Binding.TABLE_META,other.texture_table.sha256)
	var second:=PackedScene.new();second.pack(node);node.free()
	var map:=Map.new();var pool:=configure(map,fixture,blank);map._model_preparation.inflight_byte_limit=1024
	var a:String=fixture.content_root.path_join("tight-a.glb");var b:String=fixture.content_root.path_join("tight-b.glb")
	map._model_preparation.candidate_provider=func(path:String)->Dictionary:return fixture.candidate if path==a else other
	map._model_preparation.candidate_reader=func(path:String,descriptor:Dictionary)->Dictionary:return {"error":OK,"compiled":true,"packed":blank if path==a else second,"source_digest":descriptor.source_sha}
	map.paths=[a,b];root.add_child(map);map.start("private-fixture")
	var deadline:=Time.get_ticks_msec()+5000
	while not map.completed and Time.get_ticks_msec()<deadline:await process_frame
	check(map.completed and map.observed_error==OK,"two oversized tables complete under tiny working budget without retained-ticket deadlock")
	map.free();check(pool.admission.byte_limit==1024 and pool.admission.count()==0,"multi-table teardown restores original budget exactly")

func cancellation_case(fixture:Object,blank:PackedScene)->void:
	var map:=Map.new();var pool:=configure(map,fixture,blank);map._model_preparation.inflight_byte_limit=1024
	map._native_resident_bridge.lookup_override=func(_key:String,_row:Dictionary)->Dictionary:return {"pending":true}
	map.paths=[fixture.content_root.path_join("cancel.glb")];root.add_child(map);map.start("private-fixture")
	var deadline:=Time.get_ticks_msec()+5000;var run:RefCounted
	while Time.get_ticks_msec()<deadline:
		map._model_preparation._mutex.lock();run=map._model_preparation._native_resident_run;map._model_preparation._mutex.unlock()
		if run!=null and run.snapshot().pending==1 and pool.admission.active_workers()==0:break
		await process_frame
	check(run!=null and run.snapshot().pending==1 and pool.admission.active_workers()==0,"paused main reply holds no worker slot or exclusive geometry lease")
	check(map._thread.is_alive() and not map.completed,"pending-only request is real external progress, not false OOM")
	map.set_process(false);var before:=Time.get_ticks_msec();root.remove_child(map);map.free()
	check(Time.get_ticks_msec()-before<1000,"real exit_tree cancels and joins without another main pump")
	check(run.released and run.snapshot().metadata_bytes==0 and pool.admission.count()==0 and pool.admission.byte_limit==1024,"tight-budget cancellation retires reply metadata and restores exact original budget")

func bridge_protocol_case(fixture:Object)->void:
	var bridge:=preload("res://scripts/world3d/initial_native_resident_bridge.gd").new()
	var plan:Dictionary=InitialFixture.Binding.candidate_plan(fixture.candidate,fixture.content_root,{})
	var key:String=plan.plan.rows.keys()[0];var row:Dictionary=plan.plan.rows[key]
	var held:={"hold":true};var visited:Dictionary={}
	bridge.lookup_override=func(id:String,description:Dictionary)->Dictionary:
		visited[id]=int(visited.get(id,0))+1
		return {"pending":true} if id=="held" and held.hold else lookup(key,description)
	var retired:=bridge.open_run();retired.request("old",{key:row});retired.close()
	var current:=bridge.open_run();current.request("a",{"held":row});current.request("b",{key:row})
	bridge.pump(200)
	check(current.poll("a").get("pending",false) and current.poll("b").has("tickets"),"held request cannot fence a later table in the same run")
	check(retired.poll("old").get("cancelled",false) and current.poll("b").tickets.has(key),"retired hint generation cannot cancel or supply the replacement generation")
	var calls:int=visited[key];current.request("same-key-another-table",{key:row});bridge.pump(200)
	check(visited[key]==calls and current.poll("same-key-another-table").tickets[key].texture==current.poll("b").tickets[key].texture,"same completed owner is looked up once across tables")
	bridge.release_run(retired)
	check(current.poll("b").tickets.has(key),"old scope release leaves replacement replies intact")
	held.hold=false;bridge.pump(200)
	check(current.poll("a").has("tickets"),"unblocked table can complete out of order")
	bridge.release_now();check(current.snapshot().metadata_bytes==0 and current.released,"bridge final cleanup releases every generation")
	check(preload("res://scripts/world3d/native_texture_sharing.gd").ticket(key,row).is_empty(),"production lookup rejects CPU fake texture without actual streaming registration")
	var late_bridge:=preload("res://scripts/world3d/initial_native_resident_bridge.gd").new();var late:=late_bridge.open_run()
	var holder:={"texture":InitialFixture.TextureStub.new()};var weak:WeakRef=weakref(holder.texture)
	late_bridge.lookup_override=func(_key:String,_row:Dictionary)->Dictionary:
		late.close();return {"texture":holder.texture,"source_sha":"a".repeat(64)}
	late.request("late",{key:row});late_bridge.pump(200);holder.clear()
	check(late.poll("late").get("cancelled",false) and weak.get_ref()!=null,"reply racing cancellation stays main-owned and unavailable to workers")
	late_bridge.release_now();check(weak.get_ref()==null,"late reply's final owner is released by explicit main cleanup")
