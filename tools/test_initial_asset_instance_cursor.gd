extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Components=preload("res://scripts/world3d/model_components.gd")
var checks:=0
var failures:=0
class PreparedLoader extends Loader:
	# This fixture enters after source verification, with a private template.
	# Normal end-to-end source/HTTP regressions cover that earlier transaction.
	func _reference_integrity()->bool:return true
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func template()->PackedScene:
	var model:=Node3D.new();model.name="LargePrivateSource"
	var mesh:=BoxMesh.new()
	for i:int in 1024:
		var node:=MeshInstance3D.new();node.name="Part%d"%i;node.mesh=mesh
		node.position=Vector3(i%32,0,i/32)
		var extras:Dictionary={"semantic_group":"20_Floor_L1" if i%2 else "50_Roof"}
		if i%127==0:extras.rmmo_hinge={"id":"leaf%d"%i,"pivot":[-.5,-1,0],"angle":90.,"open":.2}
		node.set_meta("extras",extras);model.add_child(node);node.owner=model
	var packed:=PackedScene.new();packed.pack(model);model.free();return packed
func projection(holder:Node)->Array:
	var result:Array=[]
	for node:Node in [holder]+holder.find_children("*","",true,false):
		var row:Dictionary={"path":str(holder.get_path_to(node))}
		if node is Node3D:row.transform=node.transform
		if node is MeshInstance3D:row.merge({"mesh":node.mesh,"shadow":node.cast_shadow,"extras":node.get_meta("extras",{})})
		result.append(row)
	return result
func run_case(mode:String,packed:PackedScene,record:Dictionary,expected:Array,component_rows:Array)->void:
	var loader:=PreparedLoader.new();loader.background_preload=true;loader._mesh_cache_allowed=false
	# Entering after parsing still requires the actual immutable source snapshot
	# used by the final publication gate; the former method override is earlier.
	loader._path=record.asset_path
	loader._source_snapshot=preload("res://scripts/world3d/document_source_snapshot.gd").read_file(loader._path)
	loader._record_meta={"rmmo_records":[record]};loader._record_order={record.uuid:0}
	loader._asset_states={record.asset_path:{"packed":packed}}
	var observed:Dictionary={"yields":0,"completed":false,"scene":null,"error":"","private":true,"holder":null,"profile":{}}
	loader.progress.connect(func(stage:String,_done:int,_total:int):
		if stage!="准备模型命名与组件":return
		observed.yields+=1;observed.private=observed.private and not loader._asset_cursor.holder.is_inside_tree()
		observed.holder=weakref(loader._asset_cursor.holder)
		if mode=="cancel":loader.cancel()
		elif mode=="free":loader.queue_free()
	)
	loader.finished.connect(func(scene:Node,_path:String,error:String):
		observed.completed=true;observed.scene=scene;observed.error=error;observed.profile=loader._profile.duplicate(true)
	)
	root.add_child(loader);loader.set_process(false);loader._build_records()
	var deadline:=Time.get_ticks_msec()+15000
	while is_instance_valid(loader) and Time.get_ticks_msec()<deadline:await process_frame
	check(not is_instance_valid(loader) and observed.yields>0 and observed.private,mode+": initial loader actually yields while the component graph remains private")
	if mode=="complete":
		if not observed.error.is_empty():print("INITIAL_ASSET_CURSOR_ERROR ",observed.error)
		check(observed.completed and observed.error.is_empty() and is_instance_valid(observed.scene),"complete: initial loader transfers the finished map once")
		if is_instance_valid(observed.scene):
			var holder:Node=observed.scene.get_child(0)
			check(projection(holder)==expected and Components.rows(holder.get_child(0))==component_rows,"complete: names, transforms, geometry, fixture identity/state and floor/roof roles match the synchronous operation")
			check(observed.profile.get("asset_instance_slices",0)>1 and observed.profile.get("asset_instance_cpu_us",0)>0,"complete: CPU slices and wall time are recorded separately")
			observed.scene.free()
	else:
		check(not observed.completed and observed.holder!=null and observed.holder.get_ref()==null,mode+": unpublished cursor graph releases without a finished-map signal")
func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	Loader.initial_cpu_capture_enabled=false;Loader.initial_static_specs_enabled=false
	var folder:="D:/code/rmmo_runtime/cache/initial_asset_cursor_%d"%Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("private-template.gltf");FileAccess.open(path,FileAccess.WRITE).store_string("{}")
	var record:Dictionary={"uuid":"instance","kind":"asset","asset_path":path,"position":[4,2,-3],"rotation":[0,24,0],"size":[1.1,.9,1.2],"collision":"walk","model_component_states":{"leaf0":.75}}
	var packed:=template();var doc:=Doc.new();var holder:Node=doc._asset(record,{"template":packed})
	var expected:=projection(holder);var rows:=Components.rows(holder.get_child(0));holder.free()
	for mode:String in ["complete","cancel","free"]:await run_case(mode,packed,record,expected,rows)
	print("INITIAL_ASSET_INSTANCE_CURSOR checks=",checks," failures=",failures);quit(1 if failures else 0)
