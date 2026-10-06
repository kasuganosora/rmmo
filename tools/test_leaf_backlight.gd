extends SceneTree
const Leaf=preload("res://scripts/world3d/leaf_backlight.gd")
const Wind=preload("res://scripts/world3d/wind_material.gd")
const Response=preload("res://scripts/world3d/wind_response.gd")
var failed:=0
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if not value:failed+=1
func _initialize()->void:
	var root_node:=Node3D.new();var leaf:=MeshInstance3D.new();var wood:=MeshInstance3D.new()
	leaf.mesh=QuadMesh.new();wood.mesh=BoxMesh.new();root_node.add_child(leaf);root_node.add_child(wood)
	var shared:=StandardMaterial3D.new();leaf.mesh.material=shared;wood.mesh.material=shared
	leaf.set_meta("extras",{"rmmo_leaf_backlight":["invalid"]});Leaf.apply(root_node)
	check(leaf.get_surface_override_material(0)==null,"invalid optical metadata has no side effects")
	leaf.set_meta("extras",{"rmmo_leaf_backlight":[.14]});Leaf.apply(root_node)
	var material:=leaf.get_active_material(0) as StandardMaterial3D
	check(material.backlight_enabled and is_equal_approx(material.backlight.srgb_to_linear().r,.14),"explicit linear transmission strength")
	check(not shared.backlight_enabled and not wood.get_active_material(0).backlight_enabled,"shared bark material unchanged")
	check(not material.emission_enabled,"transmission is lit material, not emission")
	check(Response.material_error(material).is_empty(),"leaf remains wind compatible")
	var shader:=Wind.make(material,Response.defaults(),AABB(Vector3.ZERO,Vector3.ONE))
	check(shader.get_shader_parameter("backlight_enabled")==true and shader.get_shader_parameter("backlight")==material.backlight,"wind preserves transmission")
	Leaf.apply(root_node);check(leaf.get_active_material(0).backlight==material.backlight,"reapply does not compound transmission")
	root_node.free();quit(1 if failed else 0)
