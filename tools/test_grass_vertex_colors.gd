extends SceneTree
const Grass=preload("res://scripts/world3d/grass_texture_cache.gd")
var failed:=0
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failed+=1
func surface(colored:bool)->Array:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3.ZERO,Vector3.RIGHT,Vector3.UP]:
		if colored:st.set_color(Color(.2,.4,.3,1))
		st.add_vertex(point)
	return st.commit_to_arrays()
func _initialize()->void:
	var host:=Node3D.new();var source:=StandardMaterial3D.new()
	var mixed:=MeshInstance3D.new();mixed.mesh=ArrayMesh.new()
	for colored in [true,false]:mixed.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface(colored));mixed.mesh.surface_set_material(mixed.mesh.get_surface_count()-1,source)
	mixed.material_override=source;mixed.set_meta("extras",{"rmmo_grass":true});host.add_child(mixed)
	var other:=MeshInstance3D.new();other.mesh=mixed.mesh;host.add_child(other)
	var peer:=MeshInstance3D.new();peer.mesh=mixed.mesh;peer.set_meta("extras",{"rmmo_grass":true});host.add_child(peer)
	Grass.apply(host)
	check(mixed.get_active_material(0).vertex_color_use_as_albedo,"colored grass uses root shading")
	check(not mixed.get_active_material(1).vertex_color_use_as_albedo,"uncolored grass surface retains source behavior")
	check(not other.get_active_material(0).vertex_color_use_as_albedo and not source.vertex_color_use_as_albedo,"shared non-grass material unchanged")
	check(peer.get_active_material(0)==mixed.get_active_material(0),"colored grass peers share derived material")
	var first:Material=mixed.get_active_material(0);Grass.apply(host)
	check(mixed.get_active_material(0)==first,"repeated import processing is idempotent")
	host.free();quit(failed)
