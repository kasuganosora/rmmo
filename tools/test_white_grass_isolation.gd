extends SceneTree
const Grass=preload("res://scripts/world3d/grass_texture_cache.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
class Counted extends "res://scripts/world3d/ground_cpu_mesh.gd":
	var reads:=0
	func _surface_get_arrays(slot:int)->Array:reads+=1;return surfaces[slot]
func _initialize()->void:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
	arrays[Mesh.ARRAY_COLOR]=PackedColorArray([Color.GREEN,Color.GREEN,Color.GREEN])
	var mesh:=Counted.new();mesh.surfaces=[arrays];mesh.materials=[StandardMaterial3D.new()]
	var node:=MeshInstance3D.new();node.mesh=mesh;node.set_meta("extras",{"rmmo_grass":true})
	Controls.white_materials=true;mesh.reads=0;Grass.apply(node)
	var white_ok:bool=mesh.reads==0 and node.get_surface_override_material(0)==null and not node.get_active_material(0).vertex_color_use_as_albedo
	Controls.white_materials=false;Grass.apply(node)
	var normal_ok:bool=mesh.reads==1 and node.get_active_material(0).vertex_color_use_as_albedo
	print("WHITE_GRASS_ISOLATION white=",white_ok," normal=",normal_ok)
	node.free();quit(0 if white_ok and normal_ok else 1)
