extends SceneTree
const Ranges=preload("res://scripts/world3d/asset_visibility_range.gd")
var failed:=0
func _initialize()->void:
	var node:=MeshInstance3D.new();node.mesh=BoxMesh.new()
	var bounds:Array=[-1.,0.,-1.,2.,10.,2.]
	for invalid in [{},{"begin":-1,"end":30,"bounds":bounds},{"begin":40,"end":30,"bounds":bounds},{"begin":0,"end":30,"bounds":[0,0,0,0,1,1]},{"begin":"0","end":30,"bounds":bounds}]:
		node.set_meta("extras",{"rmmo_visibility_range":invalid});Ranges.register(node)
		if node.visibility_range_begin!=0 or node.visibility_range_end!=0:failed+=1
	node.set_meta("extras",{"rmmo_visibility_range":{"begin":35,"end":85,"bounds":bounds}});Ranges.register(node)
	if node.visibility_range_begin!=35 or node.visibility_range_end!=85 or node.custom_aabb.size!=Vector3(2,10,2):failed+=1
	Ranges.register(node)
	if node.visibility_range_begin!=35:failed+=1
	node.set_meta("extras",{"rmmo_visibility_range":{"begin":85,"end":0,"bounds":bounds}});Ranges.register(node)
	if node.visibility_range_begin!=85 or node.visibility_range_end!=0:failed+=1
	node.free();print("ASSET_RANGE_FAILURES ",failed);quit(1 if failed else 0)
