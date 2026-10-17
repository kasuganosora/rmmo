extends "res://tools/test_s12_residential_published_20261017.gd"
## Same production HTTP workflow, one independently placeable masonry variant.
func prepare_published_catalog()->bool:
	expected_ids=["s10_warm_redbrick_planter"]
	var passed:=super.prepare_published_catalog()
	audit.scope="S10 warm red small-brick planter: actual shared library and HTTP discover/place/select/undo/redo/save/reopen in an owned temporary map. Original planter and formal maps unchanged."
	return passed

func model_evidence(uuid:String)->Dictionary:
	var result:=super.model_evidence(uuid)
	var holder:Node=editor._view.get_node_or_null(NodePath(uuid))
	var semantic_extras:Dictionary={}
	if holder!=null:
		for mesh:MeshInstance3D in Paint.meshes(holder):
			var extras:Dictionary=mesh.get_meta("extras",{})
			semantic_extras[str(mesh.name)]=extras.duplicate(true)
			if mesh.name=="Foliage":check(extras.get("rmmo_collision")=="none" and extras.get("rmmo_wind",{}).get("profile")=="foliage","published foliage remains nonblocking with existing wind")
	result.semantic_extras=semantic_extras
	return result
