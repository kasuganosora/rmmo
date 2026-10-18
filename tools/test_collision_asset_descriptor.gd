extends SceneTree
## Tiny REAL embedded-PNG GLB in headless mode. No author assets/maps touched.
const Cache=preload("res://scripts/world3d/collision_asset_descriptor.gd")
const Builder=preload("res://scripts/world3d/collision_asset_builder.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
var passed:=0
var failed:=0
var folder:=""
class CancelAfterWrite extends RefCounted:
	var directory:=""
	var initial:=0
	var cancelled:=false
	func is_cancelled()->bool:
		var count_:=0
		for name:String in DirAccess.get_files_at(directory):
			if name.ends_with(".rmcp"):count_+=1
		cancelled=cancelled or count_>initial
		return cancelled
class ReplaceDuringRead extends RefCounted:
	var path:=""
	var bytes:=PackedByteArray()
	var checks:=0
	var at:=4
	func is_cancelled()->bool:
		checks+=1
		if checks==at:
			var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
		return false
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failed+=1
func worker(callable:Callable)->Dictionary:
	var thread:=Thread.new();var code:int=thread.start(callable)
	if code!=OK:return {"ok":false,"reason":"test_thread"}
	while thread.is_alive():await process_frame
	return thread.wait_to_finish()
func put(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func fixture(path:String,pixel_size:int=2,allegiance:String="")->void:
	var binary:=PackedFloat32Array([0,0,0,1,0,0,0,1,0, 0,0,1,0,0,1,0,0,1, 0,0,1,0,0,1]).to_byte_array()
	var pixels:=Image.create(pixel_size,pixel_size,false,Image.FORMAT_RGBA8);pixels.fill(Color(.2,.4,.8,1))
	var png:=pixels.save_png_to_buffer();binary.append_array(png)
	var data:Dictionary={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],
		"nodes":[{"name":"Fixture","translation":[2,3,4],"children":[1,2]},
			{"name":"SolidA","mesh":0,"translation":[1,0,0],"extras":{"rmmo_collision":"block"}},
			{"name":"Nested","translation":[0,2,0],"rotation":[0,0.7071067811865475,0,0.7071067811865476],"children":[3]},
			{"name":"SolidB","mesh":0,"translation":[0,0,2],"scale":[2,1,0.5],"extras":{"rmmo_collision":"none"}}],
		"meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":2},"material":0}]}],
		"materials":[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0,"roughnessFactor":.8}}],"textures":[{"source":0}],"images":[{"bufferView":3,"mimeType":"image/png"}],
		"accessors":[{"bufferView":0,"componentType":5126,"type":"VEC3","count":3,"min":[0,0,0],"max":[1,1,0]},{"bufferView":1,"componentType":5126,"type":"VEC3","count":3},{"bufferView":2,"componentType":5126,"type":"VEC2","count":3}],
		"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":36},{"buffer":0,"byteOffset":72,"byteLength":24},{"buffer":0,"byteOffset":96,"byteLength":png.size()}],"buffers":[{"byteLength":binary.size()}]}
	if not allegiance.is_empty():data.nodes[1].extras[allegiance]=true
	var json:=JSON.stringify(data).to_utf8_buffer()
	while json.size()%4:json.append(32)
	while binary.size()%4:binary.append(0)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546c67);file.store_32(2);file.store_32(28+json.size()+binary.size())
	file.store_32(json.size());file.store_32(0x4e4f534a);file.store_buffer(json)
	file.store_32(binary.size());file.store_32(0x004e4942);file.store_buffer(binary);file.close()
func count_label(trace:Dictionary,label:String)->int:
	var result:=0
	for row:Dictionary in trace.stats:
		if row.label==label:result+=int(row.count)
	return result
func expected_entries(node:Node,pose:Transform3D=Transform3D.IDENTITY,selector:String="root",asset_root:Node=null)->Array:
	var rows:Array=[]
	if asset_root==null:asset_root=node
	if node is Node3D:pose=pose*node.transform
	if node is MeshInstance3D:
		var mesh:Mesh=node.get_meta("collision_solid",node.get_meta("paint_source",node.mesh))
		var cpu:Cpu=mesh if mesh is Cpu else mesh.get_meta("ground_cpu_cache")
		rows.append({"selector":selector,"node_path":str(asset_root.get_path_to(node)),"transform":pose,"faces":cpu._collision_faces,"collision":Io.extras_of(node).get("rmmo_collision","")})
	for index:int in node.get_child_count():rows.append_array(expected_entries(node.get_child(index),pose,selector+"/"+str(index),asset_root))
	return rows
func verify_png(prepared:Dictionary)->bool:
	# This is the actual import's texture; a fake no-image GLB cannot satisfy it.
	var mesh:MeshInstance3D=prepared.scene.find_child("SolidA",true,false)
	var material:StandardMaterial3D=mesh.get_active_material(0)
	if material==null or material.albedo_texture==null:return false
	var pixels:Image=material.albedo_texture.get_image()
	return pixels!=null and pixels.get_size()==Vector2i(2,2) and pixels.get_pixel(0,0).b>.7
func remove_fixture(directory:String)->void:
	if not Paths.allowed(directory,folder):return
	for name:String in DirAccess.get_files_at(directory):
		var path:=directory.path_join(name)
		if Paths.allowed(path,folder):DirAccess.remove_absolute(path)
	for name:String in DirAccess.get_directories_at(directory):remove_fixture(directory.path_join(name))
	DirAccess.remove_absolute(directory)
func run()->void:
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=true # Explicit source replacement diagnostic.
	var errors:=Errors.new();OS.add_logger(errors)
	folder=Paths.cache_directory("collision_asset_test_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("fixture.glb");fixture(path)
	var original:=FileAccess.get_file_as_bytes(path);var source_sha:=FileAccess.get_sha256(path)
	var estimate:=Builder.estimate(path,folder)
	check(not estimate.is_empty() and estimate.workspace_bytes==Cache.WORKSPACE_BYTES and estimate.source_estimated_bytes>0,"real PNG/GLB headers charge full importer plus independent cold workspace")
	check(Builder.estimate(path,folder+"_outside").is_empty() and Cache.candidate(path,folder+"_outside").is_empty(),"neighbor-prefix root cannot admit a source or directory")
	var denied:=await worker(Builder.build.bind(path,folder,estimate.estimated_bytes-1))
	check(not denied.ok and denied.reason=="budget_not_admitted" and not denied.has("private_preparation"),"producer refuses underfunded real import before allocating owners")
	var token:=Drainer.CancelToken.new();token.cancel()
	denied=await worker(Builder.build.bind(path,folder,estimate.estimated_bytes,token))
	check(not denied.ok and denied.cancelled and not denied.has("private_preparation"),"pre-cancel does not parse or create resources")
	var larger_path:=folder.path_join("larger.glb");fixture(larger_path,32)
	var replacement:=ReplaceDuringRead.new();replacement.path=path;replacement.bytes=FileAccess.get_file_as_bytes(larger_path);replacement.at=5
	Trace.start();denied=await worker(Builder.build.bind(path,folder,estimate.estimated_bytes,replacement));var replacement_trace:=Trace.stop()
	check(not denied.ok and count_label(replacement_trace,"deferred.model_parse")==0 and not denied.get("private_preparation",{}).has("scene"),"larger real PNG replacement after admission headers is refused before import allocation")
	Drainer.dispose_result(denied);put(path,original)
	var ledger:=Admission.new();ledger.worker_limit=1;check(ledger.reserve(path,estimate),"offline import receives actual one-worker ledger reservation")
	Trace.start();var built:=await worker(Builder.build.bind(path,folder,estimate.estimated_bytes));var build_trace:=Trace.stop();ledger.park(path)
	check(built.ok,"formal producer parses real GLB and atomically writes exact products")
	if not built.ok:
		print("BUILD_REASON ",built.get("reason"));Drainer.dispose_result(built);ledger.release(path);finish(errors);return
	check(count_label(build_trace,"deferred.model_parse")==1 and count_label(build_trace,"deferred.scene_generate")==1,"producer actually exercises existing source importer and scene generation")
	check(verify_png(built.private_preparation),"producer decodes the embedded valid 2x2 PNG through the real material path")
	var expected:=expected_entries(built.private_preparation.scene)
	check(expected.size()==2 and expected[0].transform.origin.is_equal_approx(Vector3(3,3,4)) and expected[1].transform.origin.is_equal_approx(Vector3(4,5,4)),"nested rotation scale and mesh instance transforms are exercised")
	var frozen:Dictionary=built.candidate.duplicate(true)
	check(frozen.product_count==1 and frozen.retained_bytes==36,"two transformed instances share one exact triangle product")
	var prepared_alias:Dictionary=built.private_preparation;var scene_weak:WeakRef=weakref(prepared_alias.scene)
	check(ledger.reserved_bytes==estimate.estimated_bytes,"joined resources retain complete importer and workspace charge")
	Drainer.dispose_result(built);ledger.release(path)
	check(prepared_alias.is_empty() and scene_weak.get_ref()==null and ledger.reserved_bytes==0,"main drainer clears real imported scene and aliases before lease release")
	check(not Library._scenes.has(path),"offline preparation does not publish AssetLibrary or gameplay")
	check(Cache.candidate(path,folder,source_sha)==frozen and Cache.candidate(path,folder,"a".repeat(64)).is_empty(),"small frozen directory is bound to requested complete source identity")
	Trace.start();var restored:=await worker(Cache.read.bind(frozen,folder,frozen.estimated_bytes));var read_trace:=Trace.stop()
	check(restored.ok and restored.asset is Cache.Asset,"independent collision reader returns typed CPU asset")
	if restored.ok:
		var entries:Array=restored.asset.entries();var parity:=entries.size()==expected.size()
		for i:int in mini(entries.size(),expected.size()):
			var geometry:Dictionary=restored.asset.geometry(entries[i].product)
			parity=parity and entries[i].selector==expected[i].selector and entries[i].node_path==expected[i].node_path and entries[i].transform==expected[i].transform and entries[i].collision==expected[i].collision and geometry.faces==expected[i].faces
		check(parity,"all local face bytes winding nested poses and collision-none semantics exactly match verified real import")
		check(not restored.asset is Cache.Products.Product,"asset source proof cannot masquerade as selected map or physics-ready product")
	check(count_label(read_trace,"collision_product.read")==1 and count_label(read_trace,"deferred.model_parse")==0 and count_label(read_trace,"deferred.scene_generate")==0 and count_label(read_trace,"deferred.cpu_capture")==0,"reset trace proves sidecar read enters product IO but no importer image/scene/capture path")
	denied=await worker(Cache.read.bind(frozen,folder,frozen.estimated_bytes-1));check(not denied.ok and denied.reason=="budget_not_admitted","read payload cannot allocate without retained plus scratch budget")
	denied=await worker(Cache.read.bind(frozen,folder,frozen.estimated_bytes,token));check(not denied.ok and denied.cancelled,"cancelled reader grants no Asset")
	var forged:=frozen.duplicate();forged.estimated_bytes=1
	denied=await worker(Cache.read.bind(forged,folder,1));check(not denied.ok and denied.reason=="candidate","caller cannot lower envelope bytes to bypass independent estimate validation")
	var blob:=Cache.directory(folder).path_join(str(frozen.descriptor_sha)+".rmca");var blob_bytes:=FileAccess.get_file_as_bytes(blob);var corrupt:=blob_bytes.duplicate();corrupt[corrupt.size()-1]^=1;put(blob,corrupt)
	denied=await worker(Cache.read.bind(frozen,folder,frozen.estimated_bytes));check(not denied.ok and denied.reason=="descriptor_checksum","corrupt directory fails before decoding or exposing geometry");put(blob,blob_bytes)
	var changed:=original.duplicate();var json_size:int=changed.decode_u32(12);changed.encode_float(28+json_size+12,2.0);put(path,changed)
	denied=await worker(Cache.read.bind(frozen,folder,frozen.estimated_bytes));check(not denied.ok and denied.reason=="source_changed" and not denied.has("asset"),"same-length original GLB replacement rejects old exact cache after full final SHA");put(path,original)
	var replace:=ReplaceDuringRead.new();replace.path=path;replace.bytes=changed
	denied=await worker(Cache.read.bind(frozen,folder,frozen.estimated_bytes,replace));check(not denied.ok and denied.reason=="source_changed" and replace.checks>=4,"source replaced during payload read is rejected by final complete SHA");put(path,original)
	# A real producer cancellation after the first .rmcp reaches disk must retain
	# the imported resources but cannot commit a usable asset directory.
	var cancel_path:=folder.path_join("cancel.glb");put(cancel_path,original)
	var cancel:=CancelAfterWrite.new();cancel.directory=Cache.Products.directory(folder)
	for name:String in DirAccess.get_files_at(cancel.directory):
		if name.ends_with(".rmcp"):cancel.initial+=1
	var cancelled:=await worker(Builder.build.bind(cancel_path,folder,Builder.estimate(cancel_path,folder).estimated_bytes,cancel))
	check(not cancelled.ok and cancelled.cancelled and cancelled.get("private_preparation",{}).get("scene") is Node,"in-flight producer cancellation retains generated owners for main disposal")
	check(Cache.candidate(cancel_path,folder).is_empty(),"cancelled producer leaves no published asset directory")
	var cancelled_alias:Dictionary=cancelled.get("private_preparation",{});Drainer.dispose_result(cancelled)
	check(cancelled_alias.is_empty(),"cancelled producer resource packet aliases clear on main")
	for allegiance:String in ["hostile","ally"]:
		var actor:=folder.path_join(allegiance+".glb");fixture(actor,2,allegiance)
		var actor_result:=await worker(Builder.build.bind(actor,folder,Builder.estimate(actor,folder).estimated_bytes))
		check(not actor_result.ok and actor_result.reason=="actor_semantics" and Cache.candidate(actor,folder).is_empty(),"real "+allegiance+" GLB remains on existing actor collision route")
		Drainer.dispose_result(actor_result)
	check(FileAccess.get_sha256(path)==source_sha and not Cache.enabled,"author bytes and runtime default-off mode remain unchanged")
	restored.clear();finish(errors)
func finish(errors:Logger)->void:
	remove_fixture(folder)
	OS.remove_logger(errors);check(errors.errors.is_empty(),"zero unexpected engine or script errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_ASSET_DESCRIPTOR passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
