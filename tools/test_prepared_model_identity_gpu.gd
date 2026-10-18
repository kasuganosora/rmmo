extends "res://tools/test_selected_mesh_cache.gd"
## Private desktop only: source changes must reject speculative cooked geometry.
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	folder=Paths.cache_directory("prepared_identity_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var model:=folder.path_join("source.glb")
	var maker:=preload("res://tools/test_deferred_asset_scene.gd").new()
	maker.static_fixture(model,Color(.2,.6,.3,1))
	check(Compiled.build(model).ok,"temporary model has a verified compiled candidate")
	var helper:=Fixtures.new();helper.folder=folder;helper.content_root=Paths.external_root()
	var terrain:Dictionary=helper.box("terrain",0);terrain.position=[0,0,0];terrain.size=[32,1,32];terrain.surface_id="ground";terrain.collision="walk"
	terrain.terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-2,"heights":[0,1,2,0,1,2,0,1,2],"holes":[false,false,false,false]}
	var asset:={"uuid":"model","kind":"asset","asset_path":model,"position":[4,1,4],"rotation":[0,0,0],"size":[1,1,1],"surface_id":"model","collision":"none"}
	var records:Array=[terrain,asset]
	var fixture:Dictionary=helper.fixture("map",records)
	check(Index.build(fixture.path,Paths.external_root(),records).ok,"temporary map dependency index is current")
	var map_sha:=FileAccess.get_sha256(fixture.path)
	var cold:Dictionary=await load_case(fixture.path,Vector3(4,.9,4))
	var hot:Dictionary=await load_case(fixture.path,Vector3(4,.9,4),true)
	if cold.is_empty() or hot.is_empty():quit(1);return
	check(not cold.profile.mesh_cache_candidate and hot.profile.mesh_cache_candidate and cold.geometry==hot.geometry,"speculative cached geometry is published only with matching prepared model identities")
	check(hot.profile.model_source_identity_mode=="verified_prepared_result" and hot.profile.model_source_hash_barrier_avoided==1 and hot.profile.source_hash_profile.hash_calls==0,"compiled model final SHA supplies the cook identity without a duplicate prehash barrier")
	check(hot.profile.asset_admission.native_cache_hits==1,"hot test genuinely used the compiled read path")
	var library=preload("res://scripts/world_editor/asset_library.gd")
	if not library._scenes.has(model):check(false,"live map retains its model template");hot.scene.free();quit(1);return
	var old_visual:Node=library._scenes[model].instantiate()
	var old_pixels:Dictionary=maker.capture(old_visual)
	old_visual.free()
	hot.scene.free();hot.erase("scene")
	var old_digest:=FileAccess.get_sha256(model)
	maker.static_fixture(model,Color(.8,.1,.3,1))
	check(FileAccess.get_sha256(model)!=old_digest,"model is replaced while authored map and instance stay unchanged")
	# Rebuild only the disposable directory; the compact selection identity stays
	# the same, so the old cooked candidate really reaches model reconciliation.
	check(Index.build(fixture.path,Paths.external_root(),records).ok,"replacement source has an up-to-date spatial directory")
	var changed:Dictionary=await load_case(fixture.path,Vector3(4,.9,4),true)
	if changed.is_empty():quit(1);return
	check(changed.profile.mesh_cache_selection==hot.profile.mesh_cache_selection and not changed.profile.mesh_cache_candidate and changed.profile.get("terrain_identity_restarts",0)==1,"changed prepared source rejects the same-selection cooked candidate and restarts terrain on a worker")
	var changed_visual:Node=library._scenes[model].instantiate()
	# Cook material metadata excludes embedded image pixels. Inspect the actual
	# imported texture instead of mistaking equal metadata for equal visuals.
	var changed_pixels:Dictionary=maker.capture(changed_visual)
	changed_visual.free()
	changed.scene.free();changed.erase("scene")
	check(changed.profile.asset_admission.native_cache_misses==1 and changed_pixels!=old_pixels,"stale native product falls back to current source and preserves the changed texture pixels")
	check(changed.geometry.terrain==hot.geometry.terrain,"terrain rebuilt after identity rejection is exactly equivalent")
	var fresh:Dictionary=await load_case(fixture.path,Vector3(4,.9,4))
	check(not fresh.is_empty() and fresh.profile.mesh_cache_candidate and fresh.geometry==changed.geometry,"new source identity produces a valid subsequent cooked hit")
	check(FileAccess.get_sha256(fixture.path)==map_sha,"all model transactions preserve authored map bytes")
	helper.free();maker.free()
	print("PREPARED_MODEL_IDENTITY_GPU passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
