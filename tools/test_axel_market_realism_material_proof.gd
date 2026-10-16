extends "res://tools/review_axel_market_realism_20261016.gd"
## Synthetic CPU contract tests only. This does not render or accept an asset.
var scenarios:Array=[]

func check(ok:bool,label:String)->bool:
	report.checks.append({"label":label,"ok":ok})
	if not ok:report.failures.append(label)
	return ok

func fixture(optical:bool=true)->Node3D:
	var scene:=Node3D.new();scene.name="CpuOpticalFixture"
	var names:Array=["Glass transparent","Liquid contents"]
	var recipes:Array=[{"transmittance":[.65,.8,.9],"roughness":.11},{"transmittance":[.3,.45,.2],"roughness":.21}]
	var expected_materials:Array=[]
	for index in names.size():
		expected_materials.append({"name":names[index],"normal_enabled":false,"normal_scale":1.,"roughness_factor":.82,"metallic_factor":0.,"channels":{},"explicit_optics_surface_recipes":[recipes[index],recipes[index]] if index==0 and optical else ([recipes[index]] if optical else [])})
	pinned={"expected_materials":{"baseline":{"materials":expected_materials}}};case_name="baseline"
	for group in 2:
		var node:=MeshInstance3D.new();node.name="JoinedGlassLiquid" if group==0 else "RepeatedGlass";node.mesh=ArrayMesh.new()
		for slot in (2 if group==0 else 1):
			var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
			arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD])
			node.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			var material:=StandardMaterial3D.new();material.resource_name=names[slot];material.roughness=.82;material.metallic=0
			node.mesh.surface_set_material(slot,material)
		if optical:node.set_meta("extras",{TintedGlass.KEY:{"version":1,"materials":{names[0]:recipes[0],names[1]:recipes[1]}}})
		scene.add_child(node)
	if optical:TintedGlass.apply(scene)
	return scene

func scenario(name_:String,mutation:String,expected_pass:bool)->void:
	var scene:=fixture(mutation!="ordinary")
	var first:=scene.get_child(0) as MeshInstance3D
	if mutation=="metadata_lost":first.remove_meta("extras")
	elif mutation=="roughness_changed":first.get_active_material(0).next_pass.roughness=.4
	elif mutation=="adapter_missing":first.set_surface_override_material(0,null)
	elif mutation=="glow_added":first.get_active_material(0).emission_enabled=true
	elif mutation=="source_recipe_changed":pinned.expected_materials.baseline.materials[0].explicit_optics_surface_recipes[0]={"transmittance":[.9,.9,.9],"roughness":.11}
	report={"checks":[],"failures":[]}
	var proof:=active_material_proof(scene)
	var actual_pass:bool=report.failures.is_empty()
	scenarios.append({"name":name_,"expected_pass":expected_pass,"actual_pass":actual_pass,"passed":expected_pass==actual_pass,"proof_checks":report.checks.size(),"caught_failures":report.failures.duplicate(),"surfaces":proof.surfaces,"observed_materials":proof.unique_material_names})
	scene.free()

func run()->void:
	scenario("joined two materials plus repeated glass surface retain optical recipes","none",true)
	scenario("ordinary nonoptical multi-surface material remains valid","ordinary",true)
	scenario("lost source optical metadata is rejected","metadata_lost",false)
	scenario("incorrect reflection roughness is rejected","roughness_changed",false)
	scenario("missing production optical adapter is rejected","adapter_missing",false)
	scenario("intrinsic emissive glass is rejected","glow_added",false)
	scenario("runtime optics mismatching source material recipe is rejected","source_recipe_changed",false)
	var success:bool=scenarios.all(func(row):return row.passed)
	var path:=ROOT.path_join("pipeline/material_proof_cpu_regression_v3.json")
	var evidence:Dictionary={"passed":success,"scenario_count":scenarios.size(),"scenarios":scenarios,"scope":"Synthetic CPU material contract only; no model import, native generation, GPU rendering, visual acceptance or formal publication.","script_sha256":FileAccess.get_sha256("res://tools/test_axel_market_realism_material_proof.gd"),"review_script_sha256":FileAccess.get_sha256("res://tools/review_axel_market_realism_20261016.gd"),"production_tinted_glass_sha256":FileAccess.get_sha256("res://scripts/world3d/tinted_glass.gd")}
	var saved:=put(path,evidence)
	print("MARKET_MATERIAL_PROOF_CPU ",JSON.stringify({"passed":success and saved,"scenarios":scenarios.size(),"report":path}))
	quit(0 if success and saved else 1)
