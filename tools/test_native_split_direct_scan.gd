extends SceneTree
var failures:Array[String]=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var source:=FileAccess.get_file_as_string("res://scripts/world3d/model_texture_direct_seen.gd")
	source=source.replace("extends RefCounted","extends RefCounted\nstatic var scans:int=0\nstatic var reads:int=0")
	source=source.replace("\tfor material:StandardMaterial3D in Cache._materials(root):","\tscans+=1\n\tfor material:StandardMaterial3D in Cache._materials(root):")
	source=source.replace("var value:Variant=material.get(info.name)","reads+=1\n\t\t\tvar value:Variant=material.get(info.name)")
	var script:=GDScript.new();script.source_code=source;check(script.reload()==OK,"instrument actual helper source")
	var root_:Node3D=Node3D.new();var mesh:=MeshInstance3D.new();mesh.mesh=BoxMesh.new();mesh.material_override=StandardMaterial3D.new();root_.add_child(mesh)
	root_.set_meta("rmmo_model_texture_table_v1","a".repeat(64));script.apply(root_)
	check(script.scans==0 and script.reads==0,"split-native direct publication performs no material traversal or property reads")
	script.scans=0;script.reads=0
	root_.remove_meta("rmmo_model_texture_table_v1");script.apply(root_)
	check(script.scans==1 and script.reads>0,"ordinary embedded models retain the established direct scan")
	root_.free();print("NATIVE_SPLIT_DIRECT_SCAN ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
