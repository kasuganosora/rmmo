extends "res://tools/verify_medieval_town_curves_runtime.gd"
func run() -> void:
	CURVE_MAP="D:/code/rmmo_runtime/cache/world3d/medieval_town_terrain/map.gltf"
	CURVE_RESULT="D:/code/rmmo_runtime/review_artifacts/medieval_town_terrain"
	if "--furrows" in OS.get_cmdline_user_args():
		CURVE_MAP="D:/code/rmmo_runtime/cache/world3d/medieval_town_furrows/map.gltf"
		CURVE_RESULT="D:/code/rmmo_runtime/review_artifacts/terrain_furrows/town"
	await super.run()

func river_probe(road: Array,a: Vector3,b: Vector3) -> Vector3:
	# A bridge can include long dry approaches. After moving the river, its
	# midpoint is no longer a reliable location for a riverbed assertion.
	var trace=preload("res://tools/medieval_town_river_curves.gd").new(); trace.setup(spec)
	var delta: Vector3=(b-a).normalized(); var side: Vector3=Vector3(-delta.z,0,delta.x)*(road[1]*.5+4)
	var best:=INF; var point:=Vector3.INF
	for i in range(1,20):
		for offset in [side,-side]:
			var p: Vector3=a.lerp(b,i/20.)+offset
			var distance: float=trace.signed_distance(Vector2(p.x,p.z))
			if distance<best: best=distance; point=p
	check(best< -2.,"planned river contains an off-deck bed probe beside "+str(road[0]))
	return point
