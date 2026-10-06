extends SceneTree
const Scatter=preload("res://scripts/world3d/vegetation_scatter.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
var failures:=0
func check(value: bool, message: String) -> void:
	print(("PASS: " if value else "FAIL: ")+message)
	if not value: failures+=1
func _init() -> void:
	var settings:=Scatter.defaults().merged({"id":"grove","polygon":[[0,0],[40,0],[40,10],[10,10],[10,40],[0,40]],"asset_ids":["a.glb","b.glb"]})
	check(Scatter.valid_settings(settings),"concave region accepts valid settings")
	var samples:=Scatter.candidates(settings); var again:=Scatter.candidates(settings)
	check(samples==again and samples.size()==2048,"seed produces exact repeatable bounded candidate sequence")
	check(samples.all(func(c):return Geometry2D.is_point_in_polygon(c.point,Scatter.polygon(settings.polygon))),"area sampling never places points in concave cutout")
	settings.seed=2; check(samples!=Scatter.candidates(settings),"different seed changes positions / yaw / scale")
	settings.scale_min=2; check(not Scatter.valid_settings(settings),"inverted scale range fails")
	settings.scale_min=.5; settings.asset_ids=["a","a"]; check(not Scatter.valid_settings(settings),"duplicate species rejected")
	settings.asset_ids=["a"]; settings.polygon=[[0,0],[20,20],[0,20],[20,0]]; check(not Scatter.valid_settings(settings),"self crossing boundary fails")
	settings.polygon=[[0,0],[1001,0],[1001,5],[0,5]]; check(not Scatter.valid_settings(settings),"large area guard")
	var left:=Scatter.polygon([[0,0],[5,0],[5,10],[0,10]]); var right:=Scatter.polygon([[5,0],[10,0],[10,10],[5,10]])
	check(Scatter.inside(Scatter.polygon([[2,2],[8,2],[8,8],[2,8]]),[left,right]),"footprint can span touching support slabs")
	check(not Scatter.inside(Scatter.polygon([[2,2],[11,2],[11,8],[2,8]]),[left,right]),"partial unsupported canopy footprint rejected")
	var meta:=City.defaults(); settings.polygon=[[0,0],[20,0],[20,20],[0,20]]
	meta.vegetation=[{"version":1,"settings":settings,"parts":[{"id":"veg_a","signature":"a".repeat(64)}]}]
	check(City.valid({"editor_layout":meta}),"persistent manifest is part of city schema")
	meta.vegetation.append(meta.vegetation[0]); check(not City.valid({"editor_layout":meta}),"duplicate persistent region/member identities rejected")
	print("VEGETATION_MATH_FINISHED failures=%d"%failures); quit(0 if failures==0 else 1)
