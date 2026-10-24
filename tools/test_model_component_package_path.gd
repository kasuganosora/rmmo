extends "res://tools/test_imported_building_components.gd"
## Large authored component graph, plus exact strict/trusted adaptation parity.
func package_cursor(model:Node3D,record:Dictionary)->Dictionary:
	var adapter:=Components.new()
	for method:Dictionary in adapter.get_method_list():
		if method.name=="begin" and method.args.size()>=3:return adapter.call("begin",model,record,true)
	return Components.begin(model,record)

func run()->void:
	var model:=make_model()
	var shared:Mesh=model.get_child(0).mesh
	for i:int in range(4,2007):
		var mesh:=MeshInstance3D.new();mesh.mesh=shared;mesh.name="Piece%d"%i
		mesh.set_meta("extras",{"uuid":"Piece%d"%i,"rmmo_part":{"floor":i%2,"floor_y":float(i%2)*3.4,"role":"body","part":"piece_%d"%i}})
		model.add_child(mesh)
	var descriptor:=Imported.describe(model);descriptor.source_sha="a".repeat(64)
	var record:={"uuid":"house","kind":"asset","position":[7,2,-9],"rotation":[0,37,0],"size":[2,1.5,.7],"model_building":descriptor,"model_building_states":{"front_door":1.0}}
	check(Imported.valid_record(record),"large fixture is a valid authored building")
	var start:=Time.get_ticks_usec()
	for i in 24:
		var cursor:=package_cursor(model,record)
		check(cursor.get("nodes",[]).size()==2008 and cursor.get("generic",false),"all authored components available on package path")
	var elapsed:=Time.get_ticks_usec()-start
	var expected:=make_model();var actual:=make_model()
	var small:=record.duplicate(true);small.model_building=Imported.describe(expected);small.model_building.source_sha="a".repeat(64)
	Components.advance(Components.begin(expected,small),0)
	Components.advance(package_cursor(actual,small),0)
	var same:=true
	for i in 4:
		var a:MeshInstance3D=actual.get_child(i);var b:MeshInstance3D=expected.get_child(i)
		same=same and a.name==b.name and a.transform==b.transform and Imported.same(a.get_meta("extras"),b.get_meta("extras")) and Imported.same(a.get_meta("ground_batch_record"),b.get_meta("ground_batch_record"))
	check(same and Components.rows(actual)==Components.rows(expected),"strict and package paths preserve floors, independent doors, transforms and batch ownership")
	check(not model.get_child(0).get_meta("extras").has("building"),"inspection never mutates the template or shares instance adaptation")
	var authored:=make_model();var independent:=small.duplicate(true)
	independent.model_building.members.Piece0.part="saved package annotation"
	var cursor:=package_cursor(authored,independent)
	check(not cursor.is_empty() and not authored.has_meta("model_components_error"),"mounted package does not repeat source/record descriptor authentication")
	var audited:=make_model();Components.begin(audited,independent)
	check(audited.get_meta("model_components_error","")=="authored_building_mismatch","explicit diagnostic adaptation retains independent descriptor checking")
	for node:Node in [model,expected,actual,authored,audited]:node.free()
	print("COMPONENT_PACKAGE ",JSON.stringify({"iterations":24,"meshes":2007,"inspection_us":elapsed,"checks":checks.size(),"failures":failed}))
	quit(0 if failed==0 else 1)
