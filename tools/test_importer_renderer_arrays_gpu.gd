extends SceneTree
## Real pack models: importer-decoded CPU arrays must equal the renderer readback
## byte for byte, for every unique static mesh surface.
const Hint=preload("res://scripts/world3d/importer_lod_hint.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const ASSETS:="D:/code/rmmo_runtime/packs/default/assets"
const GUILD:="7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd.glb"
var checks:=0
var failures:=0
var report:Dictionary={"models":[]}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func models()->Array:
	var names:Array=[]
	for file:String in DirAccess.get_files_at(ASSETS):
		if file.get_extension()=="glb" and file!=GUILD and FileAccess.open(ASSETS.path_join(file),FileAccess.READ).get_length()<32*1024*1024:names.append(file)
	names.sort()
	var picked:Array=[GUILD]
	for i:int in range(0,names.size(),maxi(1,names.size()/16)):picked.append(names[i])
	return picked
func generate(path:String,decode:bool)->Dictionary:
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	if document.append_from_file(path,state,0,path.get_base_dir())!=OK:return {}
	Hint.renderer_arrays_enabled=decode
	var began:=Time.get_ticks_usec();var scene:Node=Io.generate_scene(document,state,true);var elapsed:=Time.get_ticks_usec()-began
	Hint.renderer_arrays_enabled=true
	return {"scene":scene,"generate_us":elapsed}
func verify(file:String)->void:
	var path:=ASSETS.path_join(file);var control_us:=-1
	if file==GUILD:
		var control:Dictionary=generate(path,false)
		if not control.is_empty() and control.scene!=null:
			control_us=control.generate_us;preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_scene(control.scene)
	var generated:Dictionary=generate(path,true)
	if generated.is_empty() or generated.scene==null:check(false,file+" parses and generates");return
	var scene:Node=generated.scene
	var row:Dictionary={"file":file,"generate_us":generated.generate_us,"generate_without_decode_us":control_us,"meshes":0,"hinted":0,"surfaces":0,"mismatched":0,"importer_capture_us":0,"renderer_readback_us":0}
	var nodes:Array[Node]=[scene];var seen:Dictionary={}
	while not nodes.is_empty():
		var node:Node=nodes.pop_back();nodes.append_array(node.get_children())
		if not node is MeshInstance3D or not node.mesh is ArrayMesh or seen.has(node.mesh.get_instance_id()):continue
		var mesh:ArrayMesh=node.mesh;seen[mesh.get_instance_id()]=true;row.meshes+=1
		var hint:Resource=Hint.of(mesh)
		if hint==null or not hint.has_arrays(mesh):continue
		row.hinted+=1
		var began:=Time.get_ticks_usec();var counts:Dictionary={"importer_surfaces":0,"renderer_surfaces":0};var cpu:Mesh=preload("res://scripts/world3d/static_mesh_cpu_preparation.gd")._capture(mesh,counts);row.importer_capture_us+=Time.get_ticks_usec()-began
		if counts.renderer_surfaces!=0:row.mismatched+=1
		for slot:int in mesh.get_surface_count():
			began=Time.get_ticks_usec();var expected:Array=mesh.surface_get_arrays(slot);row.renderer_readback_us+=Time.get_ticks_usec()-began
			row.surfaces+=1
			if var_to_bytes(expected)!=var_to_bytes(cpu.surfaces[slot]):row.mismatched+=1
		if not hint.surfaces.is_empty():row.mismatched+=1
	check(row.hinted>0 and row.mismatched==0,"%s: %d/%d hinted meshes, %d surfaces equal renderer readback and release importer arrays"%[file,row.hinted,row.meshes,row.surfaces])
	report.models.append(row)
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_scene(scene)
func run()->void:
	check(DisplayServer.get_name()!="headless","private desktop real renderer")
	check(RenderingServer.has_method(Hint.DECODE_METHOD),"engine exposes CPU surface decode")
	for file:String in models():verify(file)
	var output:="";for arg:String in OS.get_cmdline_user_args():if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("IMPORTER_RENDERER_ARRAYS checks=",checks," failures=",failures);quit(1 if failures else 0)
