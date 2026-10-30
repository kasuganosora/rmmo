extends SceneTree
const Reader=preload("res://scripts/world3d/compiled_asset_preparation.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Preparation=preload("res://scripts/world3d/static_mesh_cpu_preparation.gd")
const Hint=preload("res://scripts/world3d/native_mesh_cpu_hint.gd")
var failures:Array=[]
var checks:=0
var output:=""
class Cancelled extends RefCounted:
	func is_cancelled()->bool:return true
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func arrays(offset:float)->Array:
	var value:Array=[];value.resize(Mesh.ARRAY_MAX)
	value[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(offset,0,0),Vector3(offset+1,0,0),Vector3(offset,1,0),Vector3(offset+1,1,0)])
	value[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD])
	value[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.UP,Vector2.ONE])
	value[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,2,1,3])
	return value
func product(directory:String)->Dictionary:
	var node:=Node3D.new();var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays(0),[],{2.0:PackedInt32Array([0,1,2])})
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays(2))
	for slot in 2:mesh.surface_set_material(slot,StandardMaterial3D.new())
	for i in 3:
		var visual:=MeshInstance3D.new();visual.mesh=mesh;node.add_child(visual);visual.owner=node;visual.name="Part_"+str(i)
	var packed:=PackedScene.new();check(packed.pack(node)==OK,"pack shared native mesh")
	var folder:=Compiled.directory(directory);DirAccess.make_dir_recursive_absolute(folder)
	var temporary:=folder.path_join("staging.scn")
	check(ResourceSaver.save(packed,temporary,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)==OK,"save native fixture outside project")
	node.free();packed=null;mesh=null
	var sha:=FileAccess.get_sha256(temporary);var path:=folder.path_join(sha+".scn")
	check(DirAccess.rename_absolute(temporary,path)==OK,"publish immutable fixture")
	# Historical native packages do not all have a direct-template reuse audit.
	# Serialized CPU geometry reuse must not depend on that separate contract.
	return {"source_path":directory.path_join("source.glb"),"product":path,"generator":"test","source_sha":"native fixture".sha256_text(),"payload_sha":sha,"bytes":FileAccess.get_file_as_bytes(path).size()}
func read(candidate:Dictionary,directory:String)->Dictionary:
	return Reader.read(candidate.source_path,candidate,directory,Callable(),true,false,"",true,true)
func exercise(candidate:Dictionary,directory:String)->Dictionary:
	var packet:=read(candidate,directory)
	check(packet.error==OK,"read native product without GLB")
	var packed:PackedScene=packet.packed;var scene:Node3D=packed.instantiate()
	var mesh:ArrayMesh=scene.get_child(0).mesh
	check(scene.get_child(1).mesh==mesh and scene.get_child(2).mesh==mesh,"native instances share same geometry owner")
	var expected:Array=[];var expected_lods:Array=[]
	for slot in mesh.get_surface_count():expected.append(mesh.surface_get_arrays(slot));expected_lods.append(Cpu.capture_lods(mesh,slot))
	var hint:Resource=Hint.of(mesh);var observer:WeakRef=weakref(hint.capture) if hint!=null else null
	var captures:=Preparation.capture(scene,true)
	var cpu:Mesh=mesh.get_meta("ground_cpu_cache")
	check(var_to_bytes(cpu.surfaces)==var_to_bytes(expected),"all decoded vertex/index/UV channels equal renderer readback")
	check(var_to_bytes(cpu.lods)==var_to_bytes(expected_lods),"index LOD tables equal renderer readback")
	check(captures.captured_meshes==1,"shared mesh is captured once")
	check(int(captures.get("native_surfaces",0))==2 and captures.renderer_surfaces==0,"native input avoids all renderer capture surfaces")
	check(not mesh.has_meta(Hint.META),"consumed hint releases its compressed owner immediately")
	var repeated:=Preparation.capture(scene,true)
	check(repeated.renderer_surfaces==0 and int(repeated.get("native_surfaces",0))==0,"repeat consumer borrows existing CPU arrays")
	check(Cpu.capture(mesh)==cpu,"standalone CPU consumer preserves the shared owner")
	scene.free();packet={};packed=null;mesh=null;cpu=null;hint=null
	check(observer==null or observer.get_ref()==null,"consumed engine capture context is not retained")
	return captures
func mutations(candidate:Dictionary,directory:String)->void:
	var packet:=read(candidate,directory);var scene:Node3D=packet.packed.instantiate();var mesh:ArrayMesh=scene.get_child(0).mesh
	var material:=StandardMaterial3D.new();material.albedo_color=Color.RED;mesh.surface_set_material(0,material)
	var cpu:=Cpu.capture(mesh)
	check(cpu.materials[0]==material,"material-only change keeps current material with native geometry")
	scene.free();packet={};mesh=null;cpu=null
	packet=read(candidate,directory);scene=packet.packed.instantiate();mesh=scene.get_child(0).mesh
	mesh.clear_surfaces();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays(7))
	cpu=Cpu.capture(mesh)
	check(var_to_bytes(cpu.surfaces[0])==var_to_bytes(mesh.surface_get_arrays(0)),"geometry revision change falls back to exact live arrays")
	check(cpu.surfaces.size()==1 and not mesh.has_meta(Hint.META),"stale generation is consumed and never reused")
	scene.free();packet={};mesh=null;cpu=null
	packet=read(candidate,directory);scene=packet.packed.instantiate();mesh=scene.get_child(0).mesh
	var hint:Resource=Hint.of(mesh);var context:WeakRef=weakref(hint.capture) if hint!=null else null
	var copy:ArrayMesh=mesh.duplicate()
	check(Hint.of(copy)==null,"duplicated resource cannot consume another mesh identity")
	copy=null;scene.free();packet={};mesh=null;hint=null
	check(context==null or context.get_ref()==null,"unused context dies with native graph on cancellation")
func worker_read(candidate:Dictionary,directory:String)->Dictionary:
	var packet:=read(candidate,directory)
	var scene:Node=packet.packed.instantiate()
	packet.scene=scene;packet.cpu_profile=Preparation.capture(scene,true)
	return packet
func parallel_read(candidate:Dictionary,directory:String)->void:
	var workers:Array[Thread]=[]
	for i in 4:
		var worker:=Thread.new();check(worker.start(worker_read.bind(candidate,directory))==OK,"start independent native read");workers.append(worker)
	while workers.any(func(thread:Thread):return thread.is_alive()):await process_frame
	var owners:Dictionary={}
	for worker:Thread in workers:
		var packet:Dictionary=worker.wait_to_finish();var node:MeshInstance3D=packet.scene.get_child(0)
		check(packet.error==OK and int(packet.cpu_profile.get("native_surfaces",0))==2 and packet.cpu_profile.renderer_surfaces==0,"worker capture has no main readback request")
		check(not owners.has(node.mesh.get_instance_id()),"private native load owns an independent mesh")
		owners[node.mesh.get_instance_id()]=true;packet.scene.free();packet={}
	var cancelled:=read(candidate,directory);var scene:Node=cancelled.packed.instantiate()
	var mesh:ArrayMesh=scene.get_child(0).mesh;var hint:Resource=Hint.of(mesh)
	var context:WeakRef=weakref(hint.capture) if hint!=null else null
	var profile:=Preparation.capture(scene,true,Cancelled.new())
	check(profile.get("cancelled",false) and profile.captured_meshes==0,"cancelled private preparation consumes no geometry")
	scene.free();mesh=null;hint=null;cancelled={}
	check(context==null or context.get_ref()==null,"cancelled worker graph releases unused native bytes")
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/"):printerr("external output required");quit(2);return
	Reader.native_cpu_handoff_enabled=not "--without-native-handoff" in OS.get_cmdline_user_args()
	var directory:=output.get_base_dir().path_join("content");DirAccess.make_dir_recursive_absolute(directory)
	var candidate:=product(directory)
	check(not FileAccess.file_exists(candidate.source_path),"logical GLB is absent")
	var plain:=Reader.read(candidate.source_path,candidate,directory,Callable(),true,false,"",true)
	check(plain.error==OK and not plain.has("native_cpu_hint_meshes"),"audit/export readers do not request transient CPU ownership")
	check(Compiled._valid_packed(plain.packed),"plain native graph remains valid for offline footprint/export audits")
	plain={}
	var capture:=exercise(candidate,directory)
	mutations(candidate,directory)
	if Reader.native_cpu_handoff_enabled:await parallel_read(candidate,directory)
	await process_frame;await process_frame
	var result:={"checks":checks,"failures":failures,"capture":capture,"enabled":Reader.native_cpu_handoff_enabled}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print(JSON.stringify(result));quit(0 if failures.is_empty() else 1)
