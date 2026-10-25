extends SceneTree
## Pure dependency enumeration. No real map, files or renderer are touched.
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
var passed:=0
var failed:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failed+=1
func _initialize()->void:
	var base:Dictionary={"texture_path":"base.png","normal_path":"normal.png","normal_format":"directx","height_path":"height.png"}
	var extra:Dictionary={"texture_path":"extra.png","ao_path":"base.png"}
	var terrain:Dictionary={"terrain_material":base,"terrain_regions":{"materials":[extra]},"terrain_depth_blend":{"sand_material":base,"rock_material":extra,"transition_material":extra}}
	var expected:Dictionary={"base.png":["base.png",false],"normal.png|flip_y":["normal.png",true],"height.png":["height.png",false],"extra.png":["extra.png",false]}
	check(Prep.sources(terrain)==expected,"terrain layers, transitions and height enter one deduplicated dependency plan")
	var road:Dictionary={"road_kerb_material":base,"surface_paint":[{"material":extra}]}
	check(Prep.sources(road)==expected,"road kerb and painted surfaces prepare all declared images")
	var prefab:Dictionary={"house_prefab":{"sha256":"fixture"},"prefab_materials":[base],"surface_paint":[{"material":extra}]}
	check(Prep.sources(prefab)==expected,"prefab surface overrides are included alongside frozen materials")
	check(Prep.sources({"banner":{"material":extra}}).size()==2,"banner material participates without a prefab")
	check(Prep.sources({"bridge_materials":{"deck":base},"rock_bank_materials":{"stone":extra},"fortification_materials":{"wall":base}})==expected,"procedural structural material dictionaries are covered")
	check(Prep.sources({}).is_empty(),"unpainted records require no texture work")
	var many:Array=[]
	for index:int in Prep.MAX_SOURCES+1:many.append({"texture_path":"image_%d.png"%index})
	check(Prep.sources({"prefab_materials":many,"house_prefab":{}}).is_empty(),"optional preparation retains its bounded source count")
	check(Prep.valid_sources(expected),"expanded dependencies retain the existing source key contract")
	print("TEXTURE_SOURCE_COVERAGE ",passed," passed, ",failed," failed")
	quit(1 if failed else 0)
