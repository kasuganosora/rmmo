extends SceneTree
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const RoadFixture=preload("res://tools/test_native_road_preparation.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var helper:=RoadFixture.new();var records:Array=[];var compact:Array=[];var sizes:Dictionary={}
	for i:int in 326:
		var row:Dictionary=helper.road();row.uuid="road_%d"%i
		row.position=[(i%20)*32.,i*.01,(i/20)*32.];row.rotation=[0,i%180,0]
		row.road_mesh.kerbs=[]
		for j:int in 8:row.road_mesh.kerbs.append(helper.part(j%2==0,j%3==0))
		if i%2==0:row.road_mesh.grade=[.03,-.02]
		else:row.road_mesh.elevations=[[.2,.3,.25,.4]]
		if i==0:row.event={"type":"custom"} # Unknown behavior remains eager/global.
		records.append(row)
		var digest:=str(i).sha256_text();sizes[digest]=4096
		compact.append({"rmmo_ref":{"uri":"fixture.rmres","sha256":digest,"length":128}})
	var began:=Time.get_ticks_usec()
	var expected:Dictionary=Index._build_rows(records,compact,sizes,Paths.external_root(),4)
	var old_us:=Time.get_ticks_usec()-began;var new_us:=-1
	check(expected.ok and expected.rows.size()==326,"diagnostic classification builds the complete road directory")
	if not OS.get_cmdline_user_args().has("--baseline"):
		var indexer:=Index.new();began=Time.get_ticks_usec()
		var actual:Dictionary=indexer.callv("_build_rows",[records,compact,sizes,Paths.external_root(),4,Callable(),{},true])
		new_us=Time.get_ticks_usec()-began
		check(actual.ok and actual.rows==expected.rows and actual.models==expected.models,"trusted package projection exactly matches every diagnostic row and memory estimate")
		check(actual.rows[0].classification=="global" and actual.rows[0].reason=="unknown_geometry","unknown behaviors retain conservative eager classification")
		check(actual.rows[1].reason=="native_road","trusted road retains its spatial bounds and normal preparation route")
	var invalid:Dictionary=helper.road();invalid.road_mesh.polygons[0].reverse()
	check(Index._classify(invalid,Paths.external_root(),{}).classification=="global","explicit diagnostic classifier still rejects invalid road topology")
	helper.free();print("TRUSTED_ROAD_INDEX ",JSON.stringify({"rows":326,"diagnostic_us":old_us,"trusted_us":new_us,"failures":failures}))
	quit(1 if failures else 0)
