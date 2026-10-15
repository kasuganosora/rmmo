extends SceneTree
## Pure CPU regressions; no editor, live map, resources or GPU are written.
const Placement=preload("res://scripts/world_editor/residential_placement_tools.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Fit=preload("res://scripts/world3d/road_terrain_fit.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
var checks:Array=[]
var failures:=0

func _init()->void:run.call_deferred()

func check(ok:bool,label:String,detail:Dictionary={})->void:
	checks.append({"ok":ok,"label":label,"detail":detail})
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func field(id:String,center_z:float,depth:float,height:float=0.,cells:int=20)->Dictionary:
	var heights:Array=[];heights.resize((cells+1)*(cells+1));heights.fill(0.)
	var holes:Array=[];holes.resize(cells*cells);holes.fill(false)
	return {"uuid":id,"kind":"box","surface_id":"ground","position":[0.,height,center_z],"rotation":[0,0,0],"size":[20.,1.,depth],"collision":"walk","terrain_mesh":{"version":1,"columns":cells,"rows":cells,"floor":-8.,"heights":heights,"holes":holes}}

func link()->Dictionary:
	var data:=Data.defaults()
	data.roads={"nodes":[{"id":"start","position":[0.,0.,-2.]},{"id":"join","position":[0.,0.,-14.]}],"edges":[{"id":"access","from":"start","to":"join","kind":"ground","width_start":1.6,"width_end":1.6}]}
	return {"ok":true,"data":data,"points":[[0.,0.,-2.],[0.,0.,-14.]]}

func evaluate(records:Array,linked:Dictionary)->Dictionary:
	var doc:=Doc.new();doc.records=records
	var before:=var_to_bytes(doc.records)
	var result:=Placement._connector_ground(doc,linked,1.6)
	check(before==var_to_bytes(doc.records),"connector proof preserves author records")
	return result

func run()->void:
	var started:=Time.get_ticks_usec();var linked:=link()
	var seam:=evaluate([field("low",-2.,10.),field("high",-12.,10.,1.)],linked)
	check(not seam.ok and seam.get("code")=="connector_slope" and absf(seam.get("max_seam_step",0.)-1.)<.00001,"one metre seam in the middle of a complete connector rejects",seam)
	var continuous:=evaluate([field("first",-2.,10.),field("second",-12.,10.)],linked)
	check(continuous.ok and continuous.max_seam_step==0. and continuous.terrain_ids.size()==2,"continuous adjacent fields remain accepted",continuous)
	var slope:=field("slope",-7.,20.)
	for z in 21:
		for x in 21:slope.terrain_mesh.heights[z*21+x]=-(float(z)-17.)*.1
	var ramp:=evaluate([slope],linked)
	check(ramp.ok and absf(ramp.max_grade-.1)<.00001 and ramp.max_seam_step==0.,"continuous ten percent connector slope passes",ramp)
	var punctured:=field("side_hole",-7.,20.,0.,40)
	punctured.terrain_mesh.holes[12*40+21]=true
	var hole:=evaluate([punctured],linked)
	check(not hole.ok and hole.get("code")=="residential_support_coverage_gap","off-centre hole inside full connector width rejects",hole)
	var doc:=Doc.new();doc.records=[field("flat",-7.,20.)]
	var zone:={"id":"elevated_reserve","purpose":"no_build","polygon":[[-1.,-9.],[1.,-9.],[1.,-7.],[-1.,-7.]],"min_y":20.,"max_y":22.}
	doc.map_meta.editor_layout=Data.defaults();doc.map_meta.editor_layout.zones=[zone]
	var settings:=Plan.defaults().merged({"follow_terrain":true},true)
	var quick:=Placement._connector_clearance(linked,settings,[],doc.map_meta)
	check(quick.ok,"house broad phase does not reject an elevated no-build zone",quick)
	var planned:=Plan.build(linked.data.roads,settings)
	check(planned.ok,"connector native road plan builds")
	if planned.ok:
		var fitted:=Fit.fit(planned.records,doc.records,settings.lift)
		check(fitted.ok,"connector terrain projection builds")
		if fitted.ok:
			var prepared:={"records":fitted.records,"excluded":{}}
			var elevated:=Placement._candidate_clearance(prepared,doc,[])
			check(elevated.ok,"exact fitted geometry passes below elevated no-build zone",elevated)
			doc.map_meta.editor_layout.zones[0].min_y=-1.;doc.map_meta.editor_layout.zones[0].max_y=3.
			var ground_zone:=Placement._candidate_clearance(prepared,doc,[])
			check(not ground_zone.ok and ground_zone.get("code")=="reserved_zone","exact fitted geometry still rejects ground-level no-build zone",ground_zone)
	var points:Array[Vector3]=[]
	for x:float in [-.5,.5]:
		for y:float in [0.,1.]:
			for z:float in [-9.,-7.]:points.append(Vector3(x,y,z))
	var house:=Placement._connector_clearance(linked,settings,[Foot.from_points(points)],{})
	check(not house.ok and house.get("code")=="road_house_clearance","existing house XZ conservative rejection remains")
	var output:="D:/code/rmmo_runtime/review_artifacts/editor_reliability/residential_connector"
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"elapsed_ms":(Time.get_ticks_usec()-started)/1000.,"scope":"headless CPU connector geometry; no live map or GPU"},"  "))
	print("test_residential_connector: checks=%d failures=%d"%[checks.size(),failures])
	quit(1 if failures else 0)
