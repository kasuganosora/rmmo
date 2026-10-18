extends "res://tools/test_asset_residency_gpu.gd"
func run()->void:
	create_timer(180).timeout.connect(func():quit(2))
	Compiled.enabled=false
	folder=Paths.cache_directory("raw_asset_publication_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	asset_path=folder.path_join("raw.glb")
	check(textured_fixture(asset_path)==OK,"write isolated raw GLB with actual embedded texture")
	var fixture:=make_map();check(fixture.ok,"write isolated reference map without a compiled model product")
	if not fixture.ok:quit(1);return
	var path:String=fixture.path;var sha:=FileAccess.get_sha256(path)
	host=Host.new();root.add_child(host);host._ready_for_play=true;host._hud=Control.new();host.add_child(host._hud);host._status=Label.new();host.add_child(host._status)
	loader=Loader.new();loader.near_first=true;host.add_child(loader);loader.start(path,A)
	var result:Array=await loader.finished;map_root=result[0];result.clear()
	check(map_root!=null,"real initial raw model route loads")
	if map_root==null:await cleanup();quit(1);return
	host.add_child(map_root);deferred=map_root.get_node("DeferredAssets")
	navigation=Navigation.new();host.add_child(navigation);host._navigation=navigation
	host._map_data.build(map_root);host._bind_deferred_geometry(map_root,navigation)
	residency=map_root.get_node("AssetResidency");residency.set_process(false);residency.grace_msec=1
	navigation.build(map_root.get_meta("stream_library"),A);deferred.activate(host);deferred.release_demand("entry_safety")
	if not await settle(A,"raw initial A"):await cleanup();quit(1);return
	var ids:=prop_ids("prop_a");var watches:=resource_watches("prop_a")
	await settle(B,"raw B");await poll_retirement()
	check(prop_ids("prop_a").is_empty() and not prop_ids("prop_b").is_empty(),"raw cached instances preserve ordinary namespace retirement")
	await settle(C,"raw cold departure");await poll_retirement()
	check(not Assets.has_cached_scene(asset_path),"last raw instance releases its checked model template")
	await probe_released(watches,"raw departure")
	await settle(A,"raw return")
	check(prop_ids("prop_a")==ids,"worker-packed raw model restores original UUIDs")
	check(int(deferred.profile.get("worker_packed_models",0))>0 and int(deferred.profile.get("compiled_hits",0))==0,"actual deferred raw route accepts a worker-packed template without main-thread scene packing")
	check(deferred.error.is_empty() and navigation.geometry_error.is_empty() and FileAccess.get_sha256(path)==sha,"raw publication keeps source SHA and real navigation ownership")
	await cleanup();print("RAW_ASSET_PUBLICATION checks=",passed+failures," failures=",failures);quit(1 if failures else 0)
