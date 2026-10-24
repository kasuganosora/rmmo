extends "res://tools/test_imported_building_components.gd"
## Repeat the real large-part count, compare against an independent old adapter.
func large_model()->Node3D:
	var model:=make_model();model.position=Vector3(.5,.2,-.7)
	var shared:Mesh=model.get_child(0).mesh
	for i:int in range(4,2007):
		var mesh:=MeshInstance3D.new();mesh.mesh=shared;mesh.name="Piece%d"%i
		mesh.position=Vector3(i%31,.2+float(i%2)*3.4,i/31)
		mesh.set_meta("extras",{"uuid":"Piece%d"%i,"rmmo_part":{"floor":i%2,"floor_y":float(i%2)*3.4,"role":"ceiling" if i%7==0 else "body","part":"piece_%d"%i}})
		model.add_child(mesh)
	return model
func project(model:Node3D)->Array:
	var rows:Array=[]
	for node:Node in model.find_children("*","",true,false):
		rows.append([str(model.get_path_to(node)),node.transform if node is Node3D else null,node.get_meta("extras",{}),node.get_meta("ground_batch_record",{})])
	return rows
func run()->void:
	var template:=large_model();var descriptor:=Imported.describe(template);descriptor.source_sha="a".repeat(64)
	var record:={"uuid":"house","kind":"asset","position":[7,2,-9],"rotation":[13,37,8],"size":[2,1.5,.7],"model_building":descriptor,"model_building_states":{"front_door":1.0}}
	var original:=project(template);var expected_bounds:Array=[]
	var expected_frame:=Transform3D(Basis.from_euler(Vector3(13,37,8)*PI/180).scaled_local(Vector3(2,1.5,.7)),Vector3(7,2,-9))
	for node:MeshInstance3D in template.get_children():expected_bounds.append(expected_frame*template.transform*node.transform*node.get_aabb())
	var actual:Node3D=template.duplicate();var began:=Time.get_ticks_usec();var cursor:=Components.begin(actual,record,true)
	while not Components.advance(cursor,100):pass
	var elapsed:=Time.get_ticks_usec()-began
	var same:=true
	for i:int in actual.get_child_count():
		var node:MeshInstance3D=actual.get_child(i);var row:Dictionary=node.get_meta("ground_batch_record")
		var extra:Dictionary=node.get_meta("extras");var bound:AABB=expected_bounds[i]
		same=same and Vector3(row.position[0],row.position[1],row.position[2]).is_equal_approx(bound.get_center()) and Vector3(row.size[0],row.size[1],row.size[2]).is_equal_approx(bound.size)
		same=same and row.building.floor==extra.rmmo_part.floor and row.building.role==extra.rmmo_part.role and row.building.id==record.uuid and extra.building==row.building
	check(same,"2007 parts retain world bounds, floor, role and batch owner under rotated nonuniform transform")
	var doors:=Components.rows(actual)
	check(doors.size()==1 and doors[0].id=="front_door" and doors[0].open==1.0,"independent door identity and open state survive bounded adaptation")
	check(project(template)==original,"large sliced adaptation leaves the source template immutable")
	var detached:Dictionary=actual.get_child(0).get_meta("ground_batch_record")
	detached.building.floor=99
	check(actual.get_child(0).get_meta("extras").building.floor!=99,"extras and batch record retain independent mutable ownership")
	for node:Node in [template,actual]:node.free()
	print("COMPONENT_ADAPTATION ",JSON.stringify({"meshes":2007,"adaptation_us":elapsed,"checks":checks.size(),"failures":failed}))
	quit(0 if failed==0 else 1)
