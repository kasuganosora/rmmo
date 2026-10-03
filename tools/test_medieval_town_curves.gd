extends SceneTree
const River=preload("res://tools/medieval_town_river_curves.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
var failed:=0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failed+=1
func run() -> void:
	var revised: bool="--terrain-revision" in OS.get_cmdline_user_args()
	var candidate:="D:/code/rmmo_runtime/cache/world3d/medieval_town_terrain/map.gltf" if revised else "D:/code/rmmo_runtime/cache/world3d/medieval_town_curves/map.gltf"
	var output:="D:/code/rmmo_runtime/review_artifacts/medieval_town_terrain/geometry_result.json" if revised else "D:/code/rmmo_runtime/review_artifacts/medieval_town_curves/geometry_result.json"
	var spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/medieval_town_layout.json"))
	if not revised and spec.has("river_previous_trace"): spec.merge(spec.river_previous_trace,true)
	var river:=River.new(); river.setup(spec); var retained:=true; var overshoot:=false
	for bank in [river.left,river.right]:
		for point in bank: retained=retained and absf(River.x_at(bank,point.y)-point.x)<.001
		for i in bank.size()-1:
			for sample in 101:
				var x:=River.x_at(bank,lerpf(bank[i].y,bank[i+1].y,sample/100.0))
				overshoot=overshoot or x<minf(bank[i].x,bank[i+1].x)-.001 or x>maxf(bank[i].x,bank[i+1].x)+.001
	check(retained and not overshoot,"river cubics retain traced banks without overshooting anchor extrema")
	var doc=Doc.open_file(candidate)
	if doc==null: check(false,"load combined curve candidate"); quit(1); return
	var shoreline_error:=0.0; var shoreline_drift:=0.0; var shallow:=0; var min_width:=INF
	for i in 701:
		var a: Vector2=river.sampled_left[i]; var b: Vector2=river.sampled_right[i]
		min_width=minf(min_width,a.distance_to(b))
		for p in [a,b]:
			var x:=clampi(floori((p.x+700)/200),0,6); var z:=clampi(floori((p.y+700)/200),0,6)
			var record: Dictionary=doc._find("town_terrain_%d_%d"%[x,z])
			var height:=Terrain.sample(record,Vector3(p.x,0,p.y)-City.vec(record.position))
			shoreline_error=maxf(shoreline_error,absf(height+1.5))
			var outside: Vector2=p+Vector2(-3 if p==a else 3,0); var inside: Vector2=p-Vector2(-3 if p==a else 3,0)
			for step in 12:
				var middle: Vector2=(outside+inside)*.5
				if sample_height(doc,middle)> -1.5: outside=middle
				else: inside=middle
			shoreline_drift=maxf(shoreline_drift,absf((outside.x+inside.x)*.5-p.x))
		var center: Vector2=(a+b)*.5; var x:=clampi(floori((center.x+700)/200),0,6); var z:=clampi(floori((center.y+700)/200),0,6)
		var r: Dictionary=doc._find("town_terrain_%d_%d"%[x,z])
		if Terrain.sample(r,Vector3(center.x,0,center.y)-City.vec(r.position))> -2: shallow+=1
	check(min_width>10 and shallow==0,"curved river stays open, with a submerged bed along all 1.4km")
	check(shoreline_error<.25,"sampled terrain meets smooth shoreline within cell interpolation tolerance: %.4fm"%shoreline_error)
	check(shoreline_drift<.5,"actual terrain/water intersection stays within 0.5m of the smooth bank: %.4fm"%shoreline_drift)
	var escaped:=false
	for r in doc.records:
		var mesh: Dictionary=r.get("road_mesh",r.get("channel_mesh",{}))
		for polygon in mesh.get("polygons",[]):
			for point in polygon:
				escaped=escaped or absf(r.position[0]+point[0]*r.size[0])>700.001 or absf(r.position[2]+point[1]*r.size[2])>700.001
	check(not escaped,"all road and water vertices stay inside the 1.4km map")
	var seam_error:=0.
	for z in 7:
		for x in 7:
			var h: Array=doc._find("town_terrain_%d_%d"%[x,z]).terrain_mesh.heights
			if x<6:
				var other: Array=doc._find("town_terrain_%d_%d"%[x+1,z]).terrain_mesh.heights
				for i in 65: seam_error=maxf(seam_error,absf(h[i*65+64]-other[i*65]))
			if z<6:
				var other: Array=doc._find("town_terrain_%d_%d"%[x,z+1]).terrain_mesh.heights
				for i in 65: seam_error=maxf(seam_error,absf(h[64*65+i]-other[i]))
	check(seam_error<.000001,"all shared terrain heights remain identical")
	var f:=FileAccess.open(output,FileAccess.WRITE)
	f.store_string(JSON.stringify({"failures":failed,"shoreline_height_error_m":shoreline_error,"shoreline_horizontal_error_m":shoreline_drift,"terrain_seam_error_m":seam_error,"candidate_sha256":FileAccess.get_sha256(candidate)},"\t")); f.close()
	print("TOWN_CURVE_GEOMETRY failures=",failed); quit(1 if failed else 0)

func sample_height(doc, p: Vector2) -> float:
	var x:=clampi(floori((p.x+700)/200),0,6); var z:=clampi(floori((p.y+700)/200),0,6)
	var r: Dictionary=doc._find("town_terrain_%d_%d"%[x,z])
	return Terrain.sample(r,Vector3(p.x,0,p.y)-City.vec(r.position))
