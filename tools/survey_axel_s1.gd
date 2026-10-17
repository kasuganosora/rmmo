extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Props=preload("res://tools/axel_house_reference_props.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
func _initialize()->void:
	var doc=Doc.open_file("D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf")
	var report:={"ground":[],"objects":[]}
	for p:Vector3 in [Vector3(295.5,0,246.5),Vector3(301,0,241),Vector3(307,0,235),Vector3(313,0,229),Vector3(318,0,224),Vector3(309.75,0,286),Vector3(310,0,277),Vector3(366,0,247),Vector3(314.94,0,253.6),Vector3(314.4,0,253.6),Vector3(317,0,253.6),Vector3(313,0,253.6),Vector3(317,0,248.75),Vector3(317,0,257.25),Vector3(331,0,248.75),Vector3(331,0,257.25),Vector3(324,0,253)]:
		var row:={"xz":[p.x,p.z],"samples":[]}
		for distance:float in [0.,2.,4.,6.,8.]:
			var at:=p+Vector3(.70710678,0,.70710678)*distance
			row.samples.append([at.x,at.z,Props.ground(doc,at)])
		report.ground.append(row)
	for id:String in ["obj_791","obj_792","obj_838","obj_839","obj_785","obj_786","obj_793","obj_794","obj_795"]:
		var r:Dictionary=doc._find(id);var box:AABB=Foot.record_shape(r).bounds
		report.objects.append({"id":id,"position":r.position,"rotation":r.rotation,"scale":r.size,"bounds_position":Props.B.arr(box.position),"bounds_size":Props.B.arr(box.size)})
	var out:=FileAccess.open("D:/code/rmmo_runtime/review_artifacts/axel_s1_alignment_20261017/survey.json",FileAccess.WRITE);out.store_string(JSON.stringify(report,"\t"));out.close();quit()
