extends SceneTree
## CPU-only entrance regressions using actual generated and frozen geometry.
const Access=preload("res://scripts/world_editor/residential_access.gd")
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const House=preload("res://scripts/world3d/house_prefab.gd")
var checks:Array=[]
var failures:=0

class Document extends RefCounted:
	var records:Array=[]

func _init()->void: run.call_deferred()

func check(passed:bool,label:String,detail:Dictionary={})->void:
	checks.append({"ok":passed,"label":label,"detail":detail})
	if not passed: failures+=1
	print(("PASS " if passed else "FAIL ")+label)

func field()->Dictionary:
	var heights:Array=[]; heights.resize(33*33); heights.fill(0.0)
	var holes:Array=[]; holes.resize(32*32); holes.fill(false)
	return {"uuid":"access_test_terrain","kind":"box","surface_id":"ground","position":[0,0,0],"rotation":[0,0,0],"size":[32,1,32],"collision":"walk","terrain_mesh":{"version":1,"columns":32,"rows":32,"floor":-8.,"heights":heights,"holes":holes}}

func native(base_height:float=.3)->Dictionary:
	return Blueprint.generate({"layout":"townhouse","template":"house","width":9.,"depth":11.,"floors":1,"floor_height":3.5,"base_height":base_height,"foundation_depth":1.,"style":"plaster","roof_axis":"depth","roof_pitch":36.,"chimney":false,"front_canopy":false})

func frozen(records:Array)->Array:
	var result:=House.bake(records)
	check(result.ok,"fixture bakes actual render and source collision payload",{"error":result.get("error","")})
	return result.get("records",[])

func obstruction(records:Array,position:Vector3,size:Vector3,part:String)->Dictionary:
	var owner:Dictionary=records[0].building.duplicate(true)
	owner.role="wall"; owner.part="main/test_"+part; owner.floor=0
	return {"uuid":"access_test_"+part,"kind":"box","surface_id":"stone","position":Blueprint.arr(position),"rotation":[0,0,0],"size":Blueprint.arr(size),"color":[.5,.5,.5],"collision":"block","building":owner}

func evaluate(records:Array,terrain:Dictionary={},extras:Array=[],distance:float=2.5)->Dictionary:
	var entrance:=Access.entrance(records,0.)
	if not entrance.ok:return entrance
	var doc:=Document.new();doc.records=[field() if terrain.is_empty() else terrain]+records+extras
	var before:=var_to_bytes(doc.records)
	var result:=Access.check(doc,records,entrance,entrance.position+entrance.outward*distance,1.6)
	check(before==var_to_bytes(doc.records),"entrance analysis does not mutate author records")
	return result

func run()->void:
	var started:=Time.get_ticks_usec()
	var plan:=native()
	check(plan.ok,"native single-house fixture generates")
	if not plan.ok:finish(started);return
	var records:=frozen(plan.records)
	if records.is_empty():finish(started);return
	var door:=Access.entrance(records,0.)
	check(door.ok,"actual frozen first-floor entrance is recognized",door)
	if not door.ok:finish(started);return
	var ordinary:=evaluate(records)
	check(ordinary.ok,"ordinary low treads and clear doorway pass",ordinary)
	for direction:float in [-1.,1.]:
		var slope:=field()
		for z in 33:
			# Vertex world Z is z - 16; slope begins outside the steps at -6.5.
			for x in 33:slope.terrain_mesh.heights[z*33+x]=direction*.1*maxf(0.,9.5-float(z))
		var sloped:=evaluate(records,slope,[],7.)
		check(sloped.ok and absf(sloped.get("max_grade",0.)-.1)<.00001,"continuous 10 percent %s across a long strip is not a step"%("descent" if direction<0. else "ascent"),sloped)
	var floor_doc:=Document.new();floor_doc.records=[field()]+records
	var elevation:=Access.elevation_limit(floor_doc,records,door)
	check(elevation.ok,"actual outermost complete tread produces an elevation bound",elevation)
	if elevation.ok:
		check(elevation.tread_distance>0.4 and absf(elevation.maximum_shift-(Access.STEP_LIMIT-.02-elevation.tread_height))<.00001,"allowed elevation derives from the actual outer tread and terrain",elevation)
		var elevated:Array=records.duplicate(true)
		for r:Dictionary in elevated:r.position[1]+=1.;r.building.floor_y+=1.
		var raised_door:=Access.entrance(elevated,0.)
		var raised_doc:=Document.new();raised_doc.records=[field()]+elevated
		var lowered:=Access.elevation_limit(raised_doc,elevated,raised_door)
		check(lowered.ok and lowered.maximum_shift<-.5 and absf(lowered.maximum_shift-(elevation.maximum_shift-1.))<.00001,"high input elevation yields a necessary downward adjustment",lowered)
		if lowered.ok:
			for r:Dictionary in elevated:r.position[1]+=lowered.maximum_shift;r.building.floor_y+=lowered.maximum_shift
			var corrected:=evaluate(elevated)
			check(corrected.ok,"applying the actual-tread elevation bound restores entrance access",corrected)
		var landing_hole:=field();var landing:Vector3=door.position+door.outward*(elevation.tread_distance+.025)
		var hx:=clampi(floori(landing.x+16),0,31);var hz:=clampi(floori(landing.z+16),0,31)
		landing_hole.terrain_mesh.holes[hz*32+hx]=true
		var hole_doc:=Document.new();hole_doc.records=[landing_hole]+records
		var no_landing:=Access.elevation_limit(hole_doc,records,door)
		check(not no_landing.ok and no_landing.get("code")=="residential_support_coverage_gap","hole beyond the outermost tread cannot produce a safe elevation bound",no_landing)

	var no_steps:Array=plan.records.filter(func(r):return r.building.role!="entry_step")
	var low_flat:=evaluate(frozen(no_steps))
	check(low_flat.ok,"30 cm unstepped threshold remains within conservative step reach",low_flat)
	var high:=native(.9)
	check(high.ok,"high-threshold negative fixture generates")
	if high.ok:
		var missing_steps:=evaluate(frozen(high.records.filter(func(r):return r.building.role!="entry_step")))
		check(not missing_steps.ok and missing_steps.get("code")=="entrance_step","90 cm threshold without treads is rejected",missing_steps)
		var decorative_steps:Array=high.records.duplicate(true)
		for record:Dictionary in decorative_steps:
			if record.building.role=="entry_step":record.collision="none"
		var non_supporting:=frozen(decorative_steps)
		var fake_treads:=evaluate(non_supporting)
		check(not fake_treads.ok and fake_treads.get("code")=="entrance_step","non-colliding decorative treads cannot support a high entrance",fake_treads)
		var decorative_doc:=Document.new();decorative_doc.records=[field()]+non_supporting
		var decorative_limit:=Access.elevation_limit(decorative_doc,non_supporting,Access.entrance(non_supporting,0.))
		check(decorative_limit.ok and decorative_limit.tread_height>.8 and decorative_limit.maximum_shift<-.5,"decorative treads cannot fake the actual outer-tread elevation bound",decorative_limit)

	var beam_sources:Array=plan.records.duplicate(true)
	beam_sources.append(obstruction(plan.records,door.position+door.outward*.75+Vector3.UP*1.15,Vector3(2.,.25,.35),"low_beam"))
	var beam:=evaluate(frozen(beam_sources))
	check(not beam.ok,"own frozen low beam cannot be ignored as part of the same house",beam)
	check(beam.has("position") or beam.has("conflicts"),"blocked own geometry reports a location or object witness",beam)
	var high_beam_sources:Array=plan.records.duplicate(true)
	high_beam_sources.append(obstruction(plan.records,door.position+door.outward*.75+Vector3.UP*2.4,Vector3(2.,.2,.35),"high_beam"))
	var high_beam:=evaluate(frozen(high_beam_sources))
	check(high_beam.ok,"beam above player headroom does not falsely block access",high_beam)
	var decorative_beam:=obstruction(plan.records,door.position+door.outward*.75+Vector3.UP*1.15,Vector3(2.,.25,.35),"decorative_beam")
	decorative_beam.collision="none"
	var beam_decoration:=frozen([decorative_beam])
	for record:Dictionary in beam_decoration:record.uuid="decoration_"+record.uuid
	check(not beam_decoration.is_empty() and beam_decoration[0].collision=="none","decorative beam is a distinct frozen no-collision record")
	var no_collision_beam:=evaluate(records+beam_decoration)
	check(no_collision_beam.ok,"non-colliding decorative geometry cannot falsely block headroom",no_collision_beam)

	var narrow_sources:Array=plan.records.duplicate(true)
	for sign_:float in [-1.,1.]:
		narrow_sources.append(obstruction(plan.records,door.position+door.outward*.65+door.side*(sign_*.36)+Vector3.UP*.8,Vector3(.18,1.6,.4),"jamb_"+str(sign_)))
	var narrow:=evaluate(frozen(narrow_sources))
	check(not narrow.ok,"narrow own doorway rejects despite the original wide door leaf",narrow)
	var small_leaf:Array=records.duplicate(true)
	for r:Dictionary in small_leaf:
		if str(r.uuid)==str(door.door_id):r.size[0]=.2
	check(not Access.entrance(small_leaf,0.).ok,"physically narrow entry leaf cannot claim a full-width passage")

	var unknown:Array=records.duplicate(true)
	for r:Dictionary in unknown:
		if r.has("fixture"):r.fixture.id="unknown_fixture"
	check(Access.entrance(unknown,0.).get("code")=="unsupported","unknown first-floor entrance semantics are unsupported")
	var multiple:Array=records.duplicate(true)
	var duplicate:Dictionary=records.filter(func(r):return str(r.get("uuid",""))==str(door.door_id))[0].duplicate(true)
	duplicate.uuid="second_entrance"; multiple.append(duplicate)
	check(Access.entrance(multiple,0.).get("code")=="unsupported","multiple entrance semantics are unsupported")

	var hole:=field();var at:Vector3=door.position+door.outward*1.8
	var x:=clampi(floori(at.x+16),0,31);var z:=clampi(floori(at.z+16),0,31)
	hole.terrain_mesh.holes[z*32+x]=true
	var missing:=evaluate(records,hole)
	check(not missing.ok and missing.get("code")=="residential_support_coverage_gap","real terrain hole in front of the steps rejects continuously",missing)
	var prop:=obstruction(plan.records,door.position+door.outward*1.8+Vector3.UP*.5,Vector3(1.,1.,.4),"loose_prop")
	prop.erase("building")
	var blocked:=evaluate(records,{},[prop])
	check(not blocked.ok and blocked.get("code")=="entrance_obstructed","independent prop still blocks the entrance corridor",blocked)
	finish(started)

func finish(started:int)->void:
	var report:={"ok":failures==0,"failures":failures,"checks":checks,"elapsed_ms":(Time.get_ticks_usec()-started)/1000.,"scope":"headless source collision geometry only; no map writes, GPU, UI, HTTP or gameplay traversal"}
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			var output:=argument.trim_prefix("--output=")
			DirAccess.make_dir_recursive_absolute(output)
			var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
			if file!=null:file.store_string(JSON.stringify(report,"  "))
	print("test_residential_access: checks=%d failures=%d elapsed_ms=%.3f"%[checks.size(),failures,report.elapsed_ms])
	quit(0 if failures==0 else 1)
