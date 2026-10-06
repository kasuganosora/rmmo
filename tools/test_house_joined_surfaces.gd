extends SceneTree
const B=preload("res://scripts/world3d/building_blueprint.gd")
const J=preload("res://scripts/world3d/joined_box_mesh.gd")
var failed:=0
func check(ok:bool,label:String)->void:
	if not ok:
		failed+=1
		if failed<10:push_error(label)
func _initialize()->void:
	var trimmed:=0;var max_faces:=0
	for preset in B.medieval_presets():
		var plan:=B.generate(preset.parameters)
		for r:Dictionary in plan.records:
			r.building.id="fixture"
			check(B.valid_record(r),preset.id+" valid "+str(r.building.part))
			if r.get("building_shape")!="joined_box":continue
			trimmed+=1;max_faces=maxi(max_faces,r.box_faces.size())
			check(B.geometry_signature(r)==B.geometry_signature(JSON.parse_string(JSON.stringify(r))),"joined surface signature survives JSON")
			var mesh:=J.mesh(r,StandardMaterial3D.new())
			var a:=mesh.surface_get_arrays(0);var vertices:PackedVector3Array=a[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=a[Mesh.ARRAY_NORMAL]
			for i in range(0,vertices.size(),3):check((vertices[i+2]-vertices[i]).cross(vertices[i+1]-vertices[i]).dot(normals[i])>0,"joined surface winding faces out")
		print("JOINED_HOUSE ",preset.id," records=",plan.records.size())
	check(trimmed>100 and max_faces<=128,"coplanar cleanup keeps paint face budget")
	print("JOINED_SURFACES_FINISHED trimmed=",trimmed," max_patches=",max_faces," failures=",failed)
	quit(1 if failed else 0)
