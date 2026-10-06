extends SceneTree
const C=preload("res://scripts/world_editor/bridge_clearance.gd")
var failures:=0
func check(ok: bool,label_: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+label_); if not ok: failures+=1
func mesh_of(faces: PackedVector3Array) -> ArrayMesh:
	var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=faces
	var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); return mesh
func _initialize() -> void:
	var mesh:=mesh_of(PackedVector3Array([Vector3(-2,3,0),Vector3(2,3,0),Vector3(.125,1.9,.12),Vector3(4,-5,0),Vector3(5,-5,0),Vector3(4,-5,1)]))
	check(is_equal_approx(C.continuous_roof(mesh,0),1.9),"continuous strip detects narrow tooth between quarter-metre samples")
	mesh=mesh_of(PackedVector3Array([Vector3(-2,0,0),Vector3(2,4,0),Vector3(2,4,1)]))
	check(is_equal_approx(C.continuous_roof(mesh,0),1),"clipping uses edge intersection height, not out-of-passage vertices")
	check(is_inf(C.continuous_roof(mesh,6)),"distant geometry does not obstruct the passage")
	print("BRIDGE_CLEARANCE_GEOMETRY_FINISHED failures=",failures); quit(1 if failures else 0)
