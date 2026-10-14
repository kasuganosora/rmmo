extends SceneTree
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Kerb=preload("res://scripts/world3d/road_kerb.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014"
func _initialize()->void:run.call_deferred()
func run()->void:
	var recipe:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("recipe.json")))
	var graph:Dictionary=recipe.graph.duplicate(true)
	graph.edges=graph.edges.filter(func(e):return e.kind=="ground")
	var settings:Dictionary=recipe.road_surface_settings.duplicate(true);settings.kerb_enabled=false
	var result:=Plan.build(graph,settings)
	if not result.ok:print(result);quit(1);return
	FileAccess.open(OUT.path_join("kerb_debug_records.json"),FileAccess.WRITE).store_string(JSON.stringify(result.records))
	var kerbs:=Kerb.attach(result.records,settings.merged({"kerb_enabled":true},true),[])
	print("KERB_DEBUG ",JSON.stringify(kerbs));quit(0 if kerbs.ok else 1)
