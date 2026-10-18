extends SceneTree
const Cursor=preload("res://scripts/world3d/asset_instance_preparation.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Components=preload("res://scripts/world3d/model_components.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func template()->PackedScene:
	var model:=Node3D.new();model.name="Legacy"
	model.set_meta("extras",{"delivery_stage":"textured_repair_v2"})
	var mesh:=BoxMesh.new();mesh.size=Vector3(2,3,1)
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.4,.6,.8);mesh.material=material
	for owner_:int in 4:
		var owner_node:=Node3D.new();owner_node.name="Owner%d"%owner_;owner_node.set_meta("extras",{"asset_id":str(owner_)})
		model.add_child(owner_node);owner_node.owner=model
		for i:int in 64:
			var node:=MeshInstance3D.new();node.name="Mesh%d"%i;node.mesh=mesh
			node.position=Vector3(i*.2,owner_,i*-.1)
			var extra:Dictionary={"semantic_group":["00_Foundation","20_Floor_L1","33_Ceilings_L1","50_Roof"][i%4]}
			if i%17==0:extra.rmmo_hinge={"id":"leaf%d"%i,"pivot":[-.5,-1,0],"angle":90.,"open":.2}
			if i%19==0:extra.rmmo_auto_lod=true
			node.set_meta("extras",extra);owner_node.add_child(node);node.owner=model
	var packed:=PackedScene.new();packed.pack(model);model.free();return packed
func projection(holder:Node3D)->Array:
	var result:Array=[]
	for node:Node in [holder]+holder.find_children("*","",true,false):
		var row:Dictionary={"path":str(holder.get_path_to(node))}
		if node is Node3D:row.transform=node.transform
		if node is MeshInstance3D:row.merge({"mesh":node.mesh,"material":node.material_override,"shadow":node.cast_shadow})
		for key:StringName in node.get_meta_list():
			if key=="_compiled_resource_owner":continue
			var value:Variant=node.get_meta(key)
			if key=="model_component_batch_sources":
				var names:Array=[]
				for member:Node in value:names.append(str(holder.get_path_to(member)))
				value=names
			row[str(key)]=value
		result.append(row)
	return result
func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var control:Script=load("D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/world_document_asset_control.gd")
	var old:RefCounted=control.new();var doc:=Doc.new();var packed:=template()
	var record:Dictionary={"uuid":"building","kind":"asset","position":[112,1,-72],"rotation":[0,34,0],"size":[1.2,.8,.9],"collision":"walk","model_component_states":{"Owner0:leaf0":.75}}
	var expected:Node3D=old._asset(record,{"template":packed});var expected_data:=projection(expected)
	var synchronous:Node3D=doc._asset(record,{"template":packed})
	check(projection(synchronous)==expected_data,"shared synchronous editor operation preserves pre-refactor hierarchy and metadata")
	synchronous.free()
	var cursor:=Cursor.new();cursor.begin(doc,record,packed)
	check(not cursor.advance(1),"large private instance yields before namespace and component passes finish")
	while not cursor.advance(100):await process_frame
	var actual:Node3D=cursor.take_holder()
	check(projection(actual)==expected_data,"sliced asset operation matches synchronous transforms, names, fixture state, batching exclusions and roles")
	check(Components.rows(actual.get_child(0))==Components.rows(expected.get_child(0)),"sliced component passes preserve the complete door identity and state table")
	check(cursor.holder==null and cursor.model==null and cursor.nodes.is_empty() and cursor.components.is_empty(),"completed private instance transfers its sole graph owner")
	actual.free();expected.free()
	for steps:int in [1,300,900]:
		cursor=Cursor.new();cursor.begin(doc,record,packed)
		var reference:WeakRef=weakref(cursor.holder)
		for i:int in steps:
			if cursor.advance(1):break
		cursor.dispose()
		check(reference.get_ref()==null and cursor.holder==null and cursor.nodes.is_empty() and cursor.components.is_empty(),"cancellation releases private namespace/component work after "+str(steps)+" steps")
	print("ASSET_INSTANCE_PREPARATION checks=",checks," failures=",failures);quit(1 if failures else 0)
