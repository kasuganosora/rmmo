extends SceneTree
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const Doc=preload("res://scripts/world3d/world_document.gd")
const Content=preload("res://tools/axel_market_layout_content.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Contact=preload("res://scripts/world3d/frozen_placement_contact.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Props=preload("res://tools/axel_house_reference_props.gd")
func _init()->void:call_deferred("run")
func run()->void:
	var path:="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf";var before:=FileAccess.get_sha256(path)
	var doc=Doc.open_file(path);var plan:=Content.read(Content.PLAN)
	var report:={"map_sha256":before,"plan_sha256":FileAccess.get_sha256(Content.PLAN),"houses":[]}
	var templates:Array=Content.read(Content.TEMPLATE_INDEX).templates
	var cache:Dictionary={}
	for h:Dictionary in plan.houses:
		var template:Dictionary=templates.filter(func(t):return t.id==h.template_id)[0]
		var source:=Content.oriented(Content.read(template.loaded_path),h.yaw)
		var at:=Vector3(h.position_xz[0],0,h.position_xz[1]);var reference:=at
		if h.has("ground_height_reference_xz"):reference=Vector3(h.ground_height_reference_xz[0],0,h.ground_height_reference_xz[1])
		at.y=float(h.get("target_ground_override",Props.ground(doc,reference)))-float(template.parameters.get("base_height",0))+.025
		for r:Dictionary in source.records:r.position=Content.B.arr(City.vec(r.position)+at)
		var shapes:=Foot.components(source.records,Vector3.ZERO,Basis.IDENTITY);var hits:Array=[]
		for r:Dictionary in doc.records:
			if not r.has("fortification"):continue
			for broad:Dictionary in Foot.record_shapes(r):
				if not Foot.batches_overlap(shapes,[broad]):continue
				hits.append({"record":r.uuid,"position":r.position,"size":r.size,"broad_overlap":true,"actual_overlap":Contact.intersects(r,shapes,broad,cache)})
		var row:={"id":h.id,"position":Content.B.arr(at),"fortification_contacts":hits}
		if h.id=="north_market_home_1":
			var isolated:=Doc.new();isolated.records=doc.records.filter(func(r):return r.has("fortification")).duplicate(true)
			var loaded:=Content.oriented(Content.read(template.loaded_path),h.yaw)
			var result:=Content.Library.place_buildings(isolated,loaded,at,h.label)
			row.native_complete_prefab_result={"ok":result.ok,"error":result.get("error",""),"conflicts":result.get("conflicts",[]),"component_count":result.get("ids",[]).size(),"native_buildings":isolated.map_meta.get("building_instances",{}).size(),"scope":"memory-only complete real N1 prefab against all saved fortifications; terrain unchanged and not included in this collision-only probe"}
		report.houses.append(row)
		print(h.id," ",JSON.stringify(hits))
	report.map_unchanged=FileAccess.get_sha256(path)==before
	FileAccess.open(OUT+"/market_frozen_placement_probe.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));quit(0)
