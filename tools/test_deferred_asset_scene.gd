extends "res://tools/test_model_parse_preparation_gpu.gd"
## Inherited _initialize dispatches only this run(). GPU execution is root-owned.
const Deferred = preload("res://scripts/world3d/deferred_asset_loader.gd")
const Manifest = preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Library = preload("res://scripts/world_editor/asset_library.gd")
const Drainer = preload("res://scripts/world3d/asset_worker_drainer.gd")
class CaptureCancel extends RefCounted:
	var calls:=0
	func is_cancelled()->bool:
		calls+=1
		return calls>=6

func static_fixture(path: String, color: Color, native: bool = false, offset: float = 0) -> void:
	var binary := PackedFloat32Array([0,0,0,1,0,0,0,1,0, 0,0,1,0,0,1,0,0,1, 0,0,1,0,0,1, .8,.9,.7,1,.7,.8,.6,1,.9,1,.8,1]).to_byte_array()
	var pixels := Image.create(2,2,false,Image.FORMAT_RGBA8);pixels.fill(color)
	var png := pixels.save_png_to_buffer();binary.append_array(png)
	var data := {"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],
		"nodes":[{"name":"Fixture","children":[1,2]},
			{"name":"Grass","mesh":0,"extras":{"rmmo_grass":true,"rmmo_leaf_backlight":[.3],"rmmo_visibility_range":{"begin":0,"end":150,"bounds":[-2,-1,-2,5,5,5]},"rmmo_collision":"none"}},
			{"name":"Plain","mesh":0,"translation":[3,0,0],"extras":{"rmmo_leaf_backlight":[.6],"rmmo_collision":"block"}}],
		"meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":2,"COLOR_0":3},"material":0}]}],
		"materials":[{"name":"Leaf","pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0,"roughnessFactor":.8},"doubleSided":true}],"textures":[{"source":0}],"images":[{"bufferView":4,"mimeType":"image/png"}],
		"accessors":[{"bufferView":0,"componentType":5126,"type":"VEC3","count":3,"min":[0,0,0],"max":[1,1,0]},{"bufferView":1,"componentType":5126,"type":"VEC3","count":3},{"bufferView":2,"componentType":5126,"type":"VEC2","count":3},{"bufferView":3,"componentType":5126,"type":"VEC4","count":3}],
		"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":36},{"buffer":0,"byteOffset":72,"byteLength":24},{"buffer":0,"byteOffset":96,"byteLength":48},{"buffer":0,"byteOffset":144,"byteLength":png.size()}],"buffers":[{"byteLength":binary.size()}]}
	if native: data.nodes[0].extras={"rmmo_format":"rmmo_gltf_map","rmmo_records":[]}
	data.nodes[0].translation=[offset,0,0]
	var bytes := JSON.stringify(data).to_utf8_buffer()
	while bytes.size()%4:bytes.append(32)
	while binary.size()%4:binary.append(0)
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546c67);file.store_32(2);file.store_32(28+bytes.size()+binary.size())
	file.store_32(bytes.size());file.store_32(0x4e4f534a);file.store_buffer(bytes)
	file.store_32(binary.size());file.store_32(0x004e4942);file.store_buffer(binary);file.close()

func capture(node: Node) -> Dictionary:
	var value: Dictionary = super.capture(node)
	if node is MeshInstance3D:
		value.visibility=[node.custom_aabb,node.visibility_range_begin,node.visibility_range_end,node.visibility_range_begin_margin,node.visibility_range_end_margin,node.visibility_range_fade_mode,node.cast_shadow]
		value.material_properties=[]
		for slot in node.mesh.get_surface_count():
			var material: Material=node.get_active_material(slot)
			var properties := {}
			if material != null:
				for info in material.get_property_list():
					var key: String=info.name
					if int(info.usage)&PROPERTY_USAGE_STORAGE==0 or key in ["resource_scene_unique_id","resource_path","script"]:continue
					var property: Variant=material.get(key)
					if property is Texture2D:
						var pixels: Image=property.get_image()
						properties[key]=[property.get_class(),pixels.get_size(),pixels.get_format(),pixels.has_mipmaps(),pixels.get_data()] if pixels!=null else [property.get_class()]
					elif not property is Object and not property is RID and not property is Callable and not property is Signal:properties[key]=property
			value.material_properties.append(properties)
	return value

func worker_result(path: String, digest: String, token: RefCounted = null, expected: Dictionary = {}, faces: bool = false) -> Dictionary:
	var worker := Thread.new()
	if worker.start(Deferred.prepare_scene.bind(path,digest,token,expected,faces))!=OK:return {"error":"test_worker_start"}
	while worker.is_alive():await process_frame
	return worker.wait_to_finish()

func test_cpu_capture_cache(path:String)->void:
	var cold:Dictionary=await worker_result(path,FileAccess.get_sha256(path))
	check(cold.error.is_empty() and cold.get("captured_meshes",0)>0 and cold.get("capture_bytes",0)>0 and cold.get("face_bytes",-1)==0,"worker captures packed geometry without allocating optional collision faces")
	if not cold.get("scene") is Node:return
	var first:MeshInstance3D=cold.scene.find_child("Plain",true,false)
	var source:Mesh=first.mesh
	var unexpanded:Mesh=source.get_meta("ground_cpu_cache")
	check(unexpanded._collision_faces.is_empty(),"no-collision demand retains lazy faces")
	Drainer.dispose_scene(cold.scene)
	var ready:Dictionary=await worker_result(path,FileAccess.get_sha256(path),null,{},true)
	check(ready.error.is_empty() and ready.get("face_bytes",0)>0 and ready.has("capture_us") and ready.has("face_us"),"requested collision soup and timings are prepared before transfer")
	if not ready.get("scene") is Node:return
	var plain:MeshInstance3D=ready.scene.find_child("Plain",true,false)
	var grass:MeshInstance3D=ready.scene.find_child("Grass",true,false)
	var cpu:Mesh=plain.mesh.get_meta("ground_cpu_cache")
	check(plain.mesh==grass.mesh and ready.captured_meshes==1,"shared mesh nodes are captured exactly once")
	check(cpu._collision_faces==plain.mesh.get_faces(),"prepared unindexed collision triangles match the engine reference")
	var original:Mesh=plain.mesh
	Drainer.synchronize_transfer()
	check(Library.cache_scene(path,ready.scene),"CPU-prepared scene packs through actual shared library")
	var a:Node=Library.instantiate(path);var b:Node=Library.instantiate(path)
	var av:MeshInstance3D=a.find_child("Plain",true,false);var bv:MeshInstance3D=b.find_child("Plain",true,false)
	check(av.mesh==original and bv.mesh==original and av.mesh.get_meta("ground_cpu_cache")==cpu and bv.mesh.get_meta("ground_cpu_cache")==cpu,"two cached instances preserve source and CPU cache object identity")
	var spec_a:Dictionary=Deferred.Stream._spec(av);var spec_b:Dictionary=Deferred.Stream._spec(bv)
	check(spec_a.collision_mesh==cpu and spec_b.collision_mesh==cpu and spec_a.collision_mesh._collision_faces==cpu._collision_faces,"first main collection reuses prepared cache and faces without recapture")
	Drainer.dispose_scene(a);Drainer.dispose_scene(b);Library._scenes.erase(path)
	# Explicit indexed/multisurface fixture, plus unsupported primitive and morph.
	var holder:=Node3D.new();var visual:=MeshInstance3D.new();holder.add_child(visual)
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP,Vector3.ONE])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,1,3,2])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);visual.mesh=mesh
	var indexed:Dictionary=Deferred._capture_static_meshes(holder,true)
	check(indexed.error.is_empty() and indexed.face_bytes==12*12 and mesh.get_meta("ground_cpu_cache")._collision_faces==mesh.get_faces(),"indexed multiple surfaces produce exact triangle soup once")
	var lines:=ArrayMesh.new();arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1]);lines.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
	visual.mesh=lines;var skipped:Dictionary=Deferred._capture_static_meshes(holder,true)
	check(skipped.captured_meshes==0 and not lines.has_meta("ground_cpu_cache"),"non-triangle source is never captured as triangle topology")
	var morph:=ArrayMesh.new();morph.add_blend_shape("Deform");arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	var blend:Array=arrays.duplicate();blend[Mesh.ARRAY_INDEX]=null
	morph.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[blend]);visual.mesh=morph
	skipped=Deferred._capture_static_meshes(holder,true)
	check(skipped.captured_meshes==0 and not morph.has_meta("ground_cpu_cache"),"morph mesh is excluded from static CPU capture")
	var token:=Drainer.CancelToken.new();token.cancel()
	var cancelled:Dictionary=Deferred._capture_static_meshes(holder,true,token)
	check(cancelled.get("cancelled",false) and is_instance_valid(holder),"capture cancellation preserves generated scene for main-thread disposal")
	visual.mesh=mesh
	var corrupt:Mesh=preload("res://scripts/world3d/ground_cpu_mesh.gd").new()
	var invalid:Array=arrays.duplicate();invalid[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,999])
	corrupt.surfaces=[invalid];mesh.set_meta("ground_cpu_cache",corrupt)
	var rejected:Dictionary=Deferred._capture_static_meshes(holder,true)
	check(not rejected.error.is_empty() and is_instance_valid(holder),"invalid captured indices fail without worker-side scene destruction")
	Drainer.dispose_scene(holder)
	var interrupted:Dictionary=await worker_result(path,FileAccess.get_sha256(path),CaptureCancel.new(),{},true)
	check(interrupted.get("cancelled",false) and interrupted.get("scene") is Node,"worker cancellation during capture returns generated scene ownership")
	if interrupted.get("scene") is Node:Drainer.dispose_scene(interrupted.scene)

func run() -> void:
	create_timer(90).timeout.connect(func():quit(2))
	var directory := Paths.cache_directory("deferred_scene_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var blue := directory.path_join("blue.glb");var red := directory.path_join("red.glb")
	static_fixture(blue,Color(.2,.4,.9,1));static_fixture(red,Color(.9,.3,.1,1))
	var retained: Array[Node]=[]
	await test_cpu_capture_cache(blue)
	for path in [blue,red]:
		check(Manifest.read(path).known,"static grass fixture is manifest-known")
		var document:=GLTFDocument.new();var state:=GLTFState.new()
		var parsed:=document.append_from_file(path,state,0,path.get_base_dir())
		var main:Node=Io.generate_scene(document,state) if parsed==OK else null
		var result:Dictionary=await worker_result(path,FileAccess.get_sha256(path))
		check(main!=null and result.error.is_empty() and result.get("scene") is Node,"worker off-tree preparation and main import succeed")
		if main!=null and result.get("scene") is Node:
			var scene:Node=result.scene;retained.append(scene)
			check(not scene.is_inside_tree() and scene.get_parent()==null,"worker returns unpublished scene")
			check(var_to_bytes(capture(main))==var_to_bytes(capture(scene)),"full capture parity including grass colors, leaf properties, images and custom visibility")
			var grass:MeshInstance3D=scene.find_child("Grass",true,false)
			var material:StandardMaterial3D=grass.get_active_material(0)
			check(material.vertex_color_use_as_albedo and material.backlight_enabled and grass.visibility_range_end==150 and grass.custom_aabb==AABB(Vector3(-2,-1,-2),Vector3(5,5,5)),"effects assertions are exercised rather than merely equal")
			main.free()
		elif main!=null:main.free()
	check(not Library._scenes.has(blue) and not Library._scenes.has(red),"worker never publishes AssetLibrary global scene cache")
	if retained.size()==2:
		var left:StandardMaterial3D=retained[0].find_child("Grass",true,false).get_active_material(0)
		var right:StandardMaterial3D=retained[1].find_child("Grass",true,false).get_active_material(0)
		check(left.albedo_texture!=right.albedo_texture and left.albedo_texture.get_image().get_pixel(0,0).b>.8 and right.albedo_texture.get_image().get_pixel(0,0).r>.8,"distinct embedded PNGs remain independent with shared grass cache")
	for node in retained:node.free()
	# Exercise shared grass canonicalization while main and worker own distinct
	# imports of the same pixels. Nodes/materials themselves must stay distinct.
	var overlap_worker:=Thread.new()
	check(overlap_worker.start(Deferred.prepare_scene.bind(blue,FileAccess.get_sha256(blue)))==OK,"main/worker overlap starts")
	var overlap_document:=GLTFDocument.new();var overlap_state:=GLTFState.new()
	var overlap_parse:=overlap_document.append_from_file(blue,overlap_state,0,blue.get_base_dir())
	var overlap_main:Node=Io.generate_scene(overlap_document,overlap_state) if overlap_parse==OK else null
	while overlap_worker.is_alive():await process_frame
	var overlap:Dictionary=overlap_worker.wait_to_finish()
	check(overlap_main!=null and overlap.get("scene") is Node and overlap.error.is_empty(),"concurrent imports complete without cache publication")
	if overlap_main!=null and overlap.get("scene") is Node:
		check(var_to_bytes(capture(overlap_main))==var_to_bytes(capture(overlap.scene)),"overlapping grass texture cache preserves complete scene parity")
	if overlap_main!=null:overlap_main.free()
	if overlap.get("scene") is Node:overlap.scene.free()
	var expected_manifest:Dictionary=Manifest.read(blue)
	var deferred_hash:Dictionary=await worker_result(blue,"",null,expected_manifest)
	check(deferred_hash.error.is_empty() and deferred_hash.get("source_digest")==FileAccess.get_sha256(blue),"deferred full SHA returns verified source digest from manifest admission")
	if deferred_hash.get("scene") is Node:deferred_hash.scene.free()
	var no_snapshot:Dictionary=await worker_result(blue,"")
	check(not no_snapshot.error.is_empty() and not no_snapshot.has("scene"),"empty digest without boundary snapshot fails closed")
	static_fixture(blue,Color(.2,.4,.9,1),false,100)
	var moved_source:Dictionary=await worker_result(blue,"",null,expected_manifest)
	check(not moved_source.error.is_empty() and not moved_source.has("scene"),"changed source JSON boundary rejects old manifest before full import")
	var cancelled_token:=Drainer.CancelToken.new();cancelled_token.cancel()
	var cancelled:Dictionary=await worker_result(blue,FileAccess.get_sha256(blue),cancelled_token)
	check(cancelled.get("cancelled",false) and not cancelled.has("scene"),"cancel before append avoids all scene generation")
	var old_digest:=FileAccess.get_sha256(blue);static_fixture(blue,Color.GREEN)
	var changed:Dictionary=await worker_result(blue,old_digest)
	check(not changed.error.is_empty() and not changed.has("scene"),"changed source hash fails before scene creation")
	var broken:=directory.path_join("broken.glb");FileAccess.open(broken,FileAccess.WRITE).store_string("invalid GLB")
	print("EXPECTED_BAD_SOURCE_BEGIN")
	var damaged:Dictionary=await worker_result(broken,FileAccess.get_sha256(broken))
	print("EXPECTED_BAD_SOURCE_END")
	check(not damaged.error.is_empty() and not damaged.has("scene"),"bad source yields no publishable node")
	var native:=directory.path_join("native.glb");static_fixture(native,Color.WHITE,true)
	var native_result:Dictionary=await worker_result(native,FileAccess.get_sha256(native))
	check(not native_result.error.is_empty() and not native_result.has("scene"),"native map extras cannot enter worker shared material branch")
	if native_result.get("scene") is Node:native_result.scene.free()
	# No capture/get_image call before publication: those calls would hide a
	# missing render-command fence at the worker-to-main ownership boundary.
	var publish_ready:Dictionary=await worker_result(red,FileAccess.get_sha256(red))
	if publish_ready.get("scene") is Node:
		Drainer.synchronize_transfer()
		check(Library.cache_scene(red,publish_ready.scene),"fresh worker scene packs and frees after explicit transfer fence without readback capture")
		Library._scenes.erase(red)
	else:check(false,"fresh publication fixture prepared")
	# Start then immediately remove the service. _exit_tree must join and free
	# an unconsumed result without ever publishing it to the shared cache.
	var service:=Deferred.new();root.add_child(service)
	service._worker=Thread.new()
	service._worker_token=Drainer.CancelToken.new()
	service._drainer=Drainer.for_tree(self)
	service._drainer.watch(service._worker,service._worker_token)
	var drainer:Node=service._drainer
	var exit_worker:Thread=service._worker
	check(exit_worker.start(Deferred.prepare_scene.bind(red,FileAccess.get_sha256(red),service._worker_token))==OK,"exit cleanup worker starts")
	var free_started:=Time.get_ticks_usec()
	service.free()
	check(Time.get_ticks_usec()-free_started<100000,"service free returns without blocking on live worker")
	var deadline:=Time.get_ticks_msec()+15000
	while exit_worker.is_started() and Time.get_ticks_msec()<deadline:await process_frame
	check(not exit_worker.is_started() and drainer.jobs.is_empty() and not Library._scenes.has(red),"render frames continue until orphan worker joins without cache publication")
	# Force the old deadlock condition deterministically: this independently
	# owned worker ignores cancellation and completes Io/texture readback while
	# the service disappears. The root drainer must keep frame progression.
	service=Deferred.new();root.add_child(service);service._worker=Thread.new()
	service._drainer=drainer;drainer.watch(service._worker,null)
	var readback_worker:Thread=service._worker
	check(readback_worker.start(Deferred.prepare_scene.bind(red,FileAccess.get_sha256(red)))==OK,"uncancellable in-flight readback worker starts")
	service.free()
	deadline=Time.get_ticks_msec()+15000
	while readback_worker.is_started() and Time.get_ticks_msec()<deadline:await process_frame
	check(not readback_worker.is_started() and drainer.jobs.is_empty(),"async drainer releases already in-flight GPU work instead of deadlocking")
	# Simulate SceneTree shutdown with no frame yields. Native command pumping
	# must also complete already in-flight readback before joining its thread.
	var shutdown_worker:=Thread.new()
	check(shutdown_worker.start(Deferred.prepare_scene.bind(red,FileAccess.get_sha256(red)))==OK,"shutdown-pump worker starts")
	Drainer.drain_shutdown(shutdown_worker)
	check(not shutdown_worker.is_started(),"shutdown renderer-command pump joins without future process frames")
	var staged:Dictionary=await worker_result(red,FileAccess.get_sha256(red))
	if staged.get("scene") is Node:
		var node:Node=staged.scene;var id:=node.get_instance_id()
		service=Deferred.new();root.add_child(service);service._scene=node;service.free()
		check(not is_instance_id_valid(id),"service exit frees already joined unpublished scene")
	else:check(false,"staged cleanup fixture prepared")
	for path in [blue,red,broken,native]:DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("DEFERRED_ASSET_SCENE failures=",failures);quit(0 if failures==0 else 1)
