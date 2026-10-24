extends "res://tools/test_sliced_native_retirement.gd"
const Native=preload("res://scripts/world3d/native_residency.gd")
const Scheduling=preload("res://tools/test_native_retirement_scheduling.gd")
func run()->void:
	var f:=setup()
	for i:int in 2200:
		var row:Dictionary=f.library[i]
		row.ground_batch_record={"uuid":"part%d"%i,"asset_path":"model%d.res"%(i%8),"house_prefab":{"sha256":"digest%d"%(i%32)}}
		if i%100==0:row.extras.fixture={"id":"door%d"%i,"kind":"door","open":float(i)/2200.}
	var expected:=Index.retirement_metadata(f.library.slice(0,2200))
	var trials:Array=[]
	for fused:bool in [false,true,true,false]:
		Index.retirement_metadata_enabled=fused
		var began:=Time.get_ticks_usec();var rows:=0
		for repeat:int in 32:
			var metadata:Dictionary=Index.retirement_metadata(f.library.slice(0,2200)) if not fused else {}
			var plan:=Index._owned_retire_plan(f.data,f.library,f.ids,true,null,true)
			if fused:metadata=plan.cleanup
			if not plan.ok or metadata!=expected:failures+=1
			rows+=plan.removed
		trials.append({"fused":fused,"us":Time.get_ticks_usec()-began,"selected_rows":rows,"cleanup_extra_scan_rows":0 if fused else rows})
	check(failures==0,"32 complete retire plans preserve all live fixture states, prefab digests and model identities")
	Index.retirement_metadata_enabled=true
	# An occupied unit must not perform the old metadata scan before refusal.
	var host:=Scheduling.Host.new();root.add_child(host);host._navigation=f.nav
	var queue:=Scheduling.Queue.new();host.add_child(queue)
	queue._doc.load_box_meshes={};queue._doc.load_material_pool={}
	var service:=Native.new();host.add_child(service);service.set_process(false)
	service._host=host;service._queue=queue;service._map=f.map;service.grace_msec=0
	service._units.unit={"entries":[{"compact_record":{"uuid":"guild"},"asset_path":""}],"bounds":AABB(Vector3(1600,0,1600),Vector3.ONE),"kind":"building"}
	service._resident.unit={"ids":f.ids,"outside_since":0}
	f.map.set_meta("stream_chunk",Vector2i(50,50));service.poll(100)
	check(service.profile.last_wait=="source_pinned" and int(service.profile.get("cleanup_prescan_rows",0))==0,"pinned 2200-part owner rejects with zero extra cleanup visits")
	check(f.library.size()==4600 and f.nav._spec_ids.size()==4600 and queue.runtime_fixture_states.is_empty(),"refusal changes neither ownership nor fixture state")
	f.map.set_meta("stream_chunk",Vector2i.ZERO);await process_frame
	service.poll(200)
	check(service.profile.retired_specs==2200 and service.profile.cleanup_plan_rows==2200 and int(service.profile.get("cleanup_prescan_rows",0))==0,"native caller consumes exactly the successful plan")
	check(queue.runtime_fixture_states==expected.fixtures,"live door states survive the actual unload")
	check(f.library.size()==2400 and f.nav._spec_ids.size()==2400,"navigation/index survivors remain exact")
	host.free();f.map.free();f={};drain()
	# Public diagnostic mode deliberately builds no reusable owning plan.
	f=setup();Index.reuse_owned_retirement_plan_enabled=false
	var generic:=Stream.retire_specs(f.map,f.ids,true,f.nav)
	check(generic.ok and generic.cleanup=={"fixtures":{},"digests":{},"model_paths":{}},"diagnostic non-owning preflight also returns safe scalar metadata")
	Index.reuse_owned_retirement_plan_enabled=true;f.map.free();f={};drain()
	print("RETIREMENT_METADATA_REUSE ",JSON.stringify({"trials":trials,"failures":failures}))
	quit(1 if failures else 0)
