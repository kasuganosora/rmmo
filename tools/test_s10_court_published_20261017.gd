extends "res://tools/test_s12_residential_published_20261017.gd"
## Same current 3D HTTP transaction/persistence contract in an owned test map.
const S10Imported=preload("res://scripts/world3d/imported_building.gd")
func prepare_published_catalog()->bool:
	expected_ids=["s10_mature_redfruit_courtyard","s10_court_shutter_house"]
	var passed:=super.prepare_published_catalog()
	for row:Dictionary in audit.get("items",[]):
		if row.id=="s10_court_shutter_house":
			var descriptor:=S10Imported.source_descriptor(row.output_path,row.input_sha)
			check(S10Imported.valid_descriptor(descriptor) and S10Imported.same(descriptor,row.entry.get("model_building",{})),"entire source/catalog descriptor survives actual JSON save")
	audit.scope="S10 tree and house: current shared-library sources, real HTTP discover/place/select/activity/undo/redo/save/reopen in a new owned cache map. Final near materials and formal-town placement are separate."
	return passed and failed==0

func test_component_id(row:Dictionary)->String:
	if row.id=="s10_court_shutter_house":
		var fixtures:Array=row.components.filter(func(member):return not str(member.id).contains("architecture:"))
		check(fixtures.size()==27,"all 27 house fixtures discovered through real HTTP")
		var entrance:="f0/north/entrance/door"
		check(fixtures.any(func(member):return member.id==entrance),"moved front entrance available through HTTP")
		return entrance if fixtures.any(func(member):return member.id==entrance) else ""
	return super.test_component_id(row)

func model_evidence(uuid:String)->Dictionary:
	var result:=super.model_evidence(uuid)
	var holder:Node=editor._view.get_node_or_null(NodePath(uuid))
	var semantic_extras:Dictionary={}
	if holder!=null:
		for mesh:MeshInstance3D in Paint.meshes(holder):
			var extra:Dictionary=mesh.get_meta("extras",{});var fields:Dictionary={}
			for key:String in ["rmmo_wind","rmmo_visibility_range","rmmo_editor_picking","rmmo_collision","rmmo_part"]:
				if extra.has(key):fields[key]=extra[key]
			semantic_extras[str(mesh.name)]=fields
	result.semantic_extras=semantic_extras
	return result
