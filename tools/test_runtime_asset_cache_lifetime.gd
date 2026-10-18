extends SceneTree
## Full real map loads and last-owner weak probes, independent of distance eviction.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Format=preload("res://scripts/world3d/world_location.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Scope=preload("res://scripts/world3d/runtime_asset_cache_scope.gd")
const Directory=preload("res://scripts/world3d/map_dependency_index.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
var checks:=0
var failures:=0
var receipt:Dictionary={"cycles":[]}
var folder:=""
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)
func fixture(path:String)->void:
	var binary:=PackedFloat32Array([-.5,0,0,.5,0,0,0,1,0]).to_byte_array()
	binary.append_array(PackedFloat32Array([0,0,1,0,.5,1]).to_byte_array())
	var image:=Image.create(2,2,false,Image.FORMAT_RGBA8);image.fill(Color(.6,.35,.12,1))
	var png:=image.save_png_to_buffer();binary.append_array(png)
	while binary.size()%4:binary.append(0)
	var data:={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"Crate","mesh":0}],"meshes":[{"primitives":[{"attributes":{"POSITION":0,"TEXCOORD_0":1},"material":0}]}],"materials":[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0,"roughnessFactor":.8}}],"textures":[{"source":0}],"images":[{"bufferView":2,"mimeType":"image/png"}],"accessors":[{"bufferView":0,"componentType":5126,"type":"VEC3","count":3,"min":[-.5,0,0],"max":[.5,1,0]},{"bufferView":1,"componentType":5126,"type":"VEC2","count":3}],"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":24},{"buffer":0,"byteOffset":60,"byteLength":png.size()}],"buffers":[{"byteLength":binary.size()}]}
	var bytes:=JSON.stringify(data).to_utf8_buffer()
	while bytes.size()%4:bytes.append(32)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546c67);file.store_32(2);file.store_32(28+bytes.size()+binary.size())
	file.store_32(bytes.size());file.store_32(0x4e4f534a);file.store_buffer(bytes)
	file.store_32(binary.size());file.store_32(0x004e4942);file.store_buffer(binary);file.close()
func make_map(asset:String,name_:String,distant_asset:String="")->String:
	var path:=folder.path_join(name_+".gltf")
	var records:Array=[{"uuid":"ground","kind":"box","surface_id":"ground","collision":"walk","position":[0,-.1,0],"rotation":[0,0,0],"size":[32,.2,32]},{"uuid":"crate","kind":"asset","asset_path":asset,"surface_id":"model","collision":"block","position":[2,0,4],"rotation":[0,0,0],"size":[1,1,1]}]
	if not distant_asset.is_empty():records.append({"uuid":"far_crate","kind":"asset","asset_path":distant_asset,"surface_id":"model","collision":"block","position":[514,0,4],"rotation":[0,0,0],"size":[1,1,1]})
	var stored:=Store.write_records(records,path,Paths.external_root())
	check(stored.ok,"write isolated native map "+name_)
	var extras:={"rmmo_format":Format.FORMAT,"rmmo_version":Format.FORMAT_VERSION,"rmmo_storage":Format.STORAGE,"rmmo_unit":"m","rmmo_records":stored.records,"rmmo_resource_dependencies":stored.dependencies,"spawn":[0,.9,4]}
	var data:={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"extras":extras}]}
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	if not distant_asset.is_empty():check(Directory.build(path,Paths.external_root(),records).ok,"build real dependency index for deferred fixture")
	return path
func load_map(path:String,near:bool=false)->Node:
	var loader:=Loader.new();loader.near_first=near;root.add_child(loader)
	var handoff:={"done":false,"scene":null,"error":""}
	loader.finished.connect(func(scene:Node,_path:String,error:String):handoff.scene=scene;handoff.error=error;handoff.done=true)
	loader.start(path,Vector3(0,.9,4))
	var deadline:=Time.get_ticks_msec()+30000
	while not handoff.done and Time.get_ticks_msec()<deadline:await process_frame
	check(handoff.done and handoff.error.is_empty() and is_instance_valid(handoff.scene),"real loader completes "+path.get_file())
	var scene:Node=handoff.scene
	handoff.scene=null
	if is_instance_valid(scene):
		root.add_child(scene)
		# Loader output can be an immutable stream directory. Exercise the same
		# residency publication as gameplay before checking actual Vulkan draws.
		var Stream=preload("res://scripts/world3d/world_stream.gd")
		var ready_until:=Time.get_ticks_msec()+10000
		while not scene.has_meta("stream_chunk") and Time.get_ticks_msec()<ready_until:
			Stream.sync(scene,scene,Vector3(2,.9,4),Stream.LOAD_BUDGET)
			await process_frame
	for i in 3:await process_frame
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	return scene
func probes(path:String)->Dictionary:
	var result:={"template":weakref(Assets._scenes[path])}
	var temporary:=Assets._instantiate(Assets._scenes[path])
	for mesh:MeshInstance3D in preload("res://scripts/world3d/surface_materials.gd").meshes(temporary):
		result.mesh=weakref(mesh.mesh)
		var material:=mesh.get_active_material(0) as BaseMaterial3D
		if material!=null:
			result.material=weakref(material)
			if material.albedo_texture!=null:result.texture=weakref(material.albedo_texture)
	Drainer.dispose_scene(temporary)
	return result
func alive(owners:Dictionary)->Dictionary:
	var result:Dictionary={}
	for key:String in owners:result[key]=owners[key].get_ref()!=null
	return result
func settle()->void:
	for i in 5:await process_frame
	Drainer.synchronize_transfer()
func run()->void:
	create_timer(150).timeout.connect(func():quit(2))
	var logger:=Errors.new();OS.add_logger(logger)
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(5,3,8);camera.look_at(Vector3(2,.5,4));camera.current=true
	var light:=DirectionalLight3D.new();root.add_child(light);light.rotation_degrees=Vector3(-45,-30,0)
	folder=Paths.cache_directory("runtime_cache_lifetime_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	var compiled_enabled:=Compiled.enabled;Compiled.enabled=false
	var created:Array[String]=[]
	for cycle in 4:
		var asset:=folder.path_join("model_%d.glb"%cycle);fixture(asset)
		created.append(asset)
		var path:=make_map(asset,"map_%d"%cycle)
		var source_sha:=FileAccess.get_sha256(path)
		var scene:=await load_map(path)
		if scene==null:continue
		var owners:=probes(asset)
		check(owners.size()==4 and not alive(owners).values().has(false),"real template/mesh/material/texture are live during map use")
		var drawn:=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		if DisplayServer.get_name()!="headless":check(drawn>0,"Vulkan renders actual source objects before retirement")
		scene.free();scene=null
		await settle()
		var remaining:=alive(owners)
		var cached:=0
		for path_:String in created:
			if Assets.has_cached_scene(path_):cached+=1
		receipt.cycles.append({"cache_present":Assets.has_cached_scene(asset),"alive":remaining,"retained_fixture_templates":cached,"rendered_objects":drawn})
		check(not Assets.has_cached_scene(asset),"map destruction releases its cached model template")
		check(not remaining.values().has(true),"last map destruction releases actual mesh/material/texture owners")
		check(FileAccess.get_sha256(path)==source_sha,"map lifecycle preserves authored bytes")
	for asset:String in created:Assets.evict_cached_scene(asset)
	if not OS.get_cmdline_user_args().has("--cycles-only"):
		await ownership_contracts(created[0])
		await deferred_lifetime(created[0])
		await cancelled_load(created[0])
	Compiled.enabled=compiled_enabled
	OS.remove_logger(logger)
	check(logger.errors.is_empty(),"zero unexpected engine or script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	receipt.checks=checks;receipt.failures=failures
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file:=FileAccess.open(arg.trim_prefix("--out="),FileAccess.WRITE);file.store_string(JSON.stringify(receipt,"\t"));file.close()
	print("RUNTIME_CACHE_LIFETIME checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func ownership_contracts(asset:String)->void:
	var scene:=await load_map(make_map(asset,"handoff"))
	var owners:=probes(asset)
	root.remove_child(scene)
	await settle()
	check(Assets.has_cached_scene(asset) and not alive(owners).values().has(false),"temporary detach retains cache for staged handoff and rollback")
	root.add_child(scene)
	var shared:=Node3D.new();root.add_child(shared)
	Scope.claim(shared,asset)
	check(Scope._scopes.size()==2,"each map has one weak cache scope")
	var scopes:=[weakref(scene.get_meta(Scope.META)),weakref(shared.get_meta(Scope.META))]
	scene.free();scene=null
	await settle()
	check(Assets.has_cached_scene(asset) and not alive(owners).values().has(false),"outgoing map cannot evict an incoming map's exact shared template")
	shared.free();shared=null
	await settle()
	check(not Assets.has_cached_scene(asset) and not alive(owners).values().has(true),"last shared map releases template and all visual resources")
	check(scopes[0].get_ref()==null and scopes[1].get_ref()==null and Scope._scopes.is_empty(),"weak registry and metadata leave no scope owner behind")
	# A live foreign instance keeps its geometry independently of the cache.
	scene=await load_map(make_map(asset,"foreign_instance"))
	var instance:=Assets._instantiate(Assets._scenes[asset]);root.add_child(instance)
	owners=probes(asset)
	scene.free();scene=null
	await settle()
	check(not Assets.has_cached_scene(asset) and owners.mesh.get_ref()!=null and owners.texture.get_ref()!=null,"cache eviction preserves foreign live instance geometry and texture")
	Drainer.dispose_scene(instance);instance=null
	await settle()
	check(not alive(owners).values().has(true),"foreign instance releases remaining resources on its own lifetime")
	# Source replacement must not let an old map erase the newer packed owner.
	scene=await load_map(make_map(asset,"old_version"))
	var old:=probes(asset)
	var replacement:=Assets.instantiate_preview(asset)
	check(replacement!=null and Assets.cache_scene(asset,replacement,FileAccess.get_sha256(asset)),"publish separate template owner for the same path")
	var latest:=probes(asset)
	shared=Node3D.new();Scope.claim(shared,asset)
	scene.free();scene=null
	await settle()
	check(Assets.has_cached_scene(asset) and latest.template.get_ref()!=null and old.template.get_ref()==null,"old map destruction preserves a replacement cache owner")
	shared.free();shared=null
	await settle()
	check(not Assets.has_cached_scene(asset) and not alive(latest).values().has(true),"off-tree failed or cancelled map also releases its private cache scope")
	# Ordinary distance retirement explicitly relinquishes the weak claim.
	scene=await load_map(make_map(asset,"distance_retirement"))
	owners=probes(asset)
	var scope:RefCounted=scene.get_meta(Scope.META)
	check(scope.release(asset) and scope._templates.is_empty() and not Assets.has_cached_scene(asset),"distance retirement can evict while its map is still alive")
	scope=null
	scene.free();scene=null
	await settle()
	check(not alive(owners).values().has(true),"scope records never retain an evicted packed scene")
	check(Scope._scopes.is_empty(),"all runtime cache scopes are reclaimed")

func deferred_lifetime(asset:String)->void:
	var distant:=folder.path_join("deferred_only.glb");fixture(distant)
	var path:=make_map(asset,"deferred",distant)
	var scene:=await load_map(path,true)
	var queue:Node=scene.get_node_or_null("DeferredAssets")
	check(queue!=null and not Assets.has_cached_scene(distant),"far unique model begins outside the initial entry closure")
	if queue==null:scene.free();return
	queue.activate(scene)
	queue.set_demand("review",AABB(Vector3(500,-2,-10),Vector3(32,8,32)))
	var deadline:=Time.get_ticks_msec()+30000
	while not queue.pending.is_empty() and queue.error.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(queue.pending.is_empty() and queue.error.is_empty() and Assets.has_cached_scene(distant),"actual deferred worker publishes a unique distant model")
	if Assets.has_cached_scene(distant):
		var owners:=probes(distant)
		check(scene.get_meta(Scope.META)._templates.has(distant),"deferred acceptance attaches cache lifetime to the map")
		scene.free();scene=null
		await settle()
		check(not Assets.has_cached_scene(distant) and not alive(owners).values().has(true),"map destruction reclaims models first loaded by deferred publication")
	else:scene.free()

func cancelled_load(asset:String)->void:
	var path:=make_map(asset,"cancelled")
	var loader:=Loader.new();loader.near_first=false;root.add_child(loader)
	var observation:={"cancelled":false,"finished":false,"owners":{}}
	loader.progress.connect(func(stage:String,_done:int,_total:int):
		if stage=="准备地图几何与材质" and Assets.has_cached_scene(asset) and not observation.cancelled:
			observation.owners=probes(asset);observation.cancelled=true;loader.cancel()
	)
	loader.finished.connect(func(_scene:Node,_path:String,_error:String):observation.finished=true)
	loader.start(path,Vector3(0,.9,4))
	var deadline:=Time.get_ticks_msec()+30000
	while is_instance_valid(loader) and Time.get_ticks_msec()<deadline:await process_frame
	check(observation.cancelled and not observation.finished and not is_instance_valid(loader),"actual load cancellation occurs after template publication and emits no success")
	await settle()
	check(not Assets.has_cached_scene(asset) and not alive(observation.owners).values().has(true),"cancelled unpublished root releases cached template and visual resources")
	check(Scope._scopes.is_empty(),"cancellation and deferred teardown leave no scope registrations")
