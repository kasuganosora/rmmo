extends "res://tools/probe_axel_tower_descent.gd"
## Reuse unchanged routes, support predicate and production loading on the
## immutable layout test candidate; write a NEW acceptance record, not history.
var loaded_helper_sha:=""
func run()->void:
	loaded_helper_sha=FileAccess.get_sha256("res://scripts/world3d/step_descent.gd")
	await super.run()
func diagnostic_sample(point:Vector3,stair:Dictionary,tick:int,elapsed:float,strict:Dictionary)->Dictionary:
	var row:=super.diagnostic_sample(point,stair,tick,elapsed,strict)
	var helper=preload("res://scripts/net/net.gd").server().world3d_authority._descent
	row.step_descent={"last_probe":helper.last_probe_reason,"contact_frame":helper._frame,"physics_frame":Engine.get_physics_frames(),"scale":xyz(world._player.scale)}
	return row
func finish(code:int=-1)->void:
	if finished:return
	finished=true
	if is_instance_valid(world) and is_instance_valid(world.get("_player")):
		stop_route();report.final_feet=xyz(feet())
		for id:String in saved_fixture_states:world.set_building_component_state("fortification:"+str(settings.get("id","")),id,saved_fixture_states[id],0.)
		saved_fixture_states.clear()
	for row:Dictionary in report.get("towers",[]):
		check(row.actual_target_reached_grounded,"complete descent reaches original exit grounded tower %d"%row.tower)
		check(not row.original_20_tick_bound_exceeded,"original 20 unsupported tick bound retained tower %d"%row.tower)
		check(row.maximum_native_airborne_ticks<=2,"no sustained airborne descent tower %d"%row.tower)
		check(row.actual_below_missing_ticks==0,"continuous real collision below descent tower %d"%row.tower)
	report.diagnostic_only=false;report.scope="Production controller descent fix: exact unchanged original routes and 20-tick support criterion; additional <=2 consecutive native airborne ticks. No geometry, capsule, speed, gravity or floor-angle changes."
	check(FileAccess.get_sha256("res://scripts/world3d/step_descent.gd")==loaded_helper_sha,"loaded descent implementation remained unchanged during run")
	report.source_sha256["res://scripts/world3d/step_descent.gd"]=loaded_helper_sha
	report.source_sha256["res://tools/review_axel_tower_descent.gd"]=FileAccess.get_sha256("res://tools/review_axel_tower_descent.gd")
	report.passed=report.get("phase","")=="complete" and failures==0 and code!=2
	report.acceptance_passed=report.passed
	report.status="passed" if report.passed else "failed"
	save_report();print("TOWER_DESCENT_FIX_RESULT ",output.path_join("result.json")," passed=",report.passed)
	quit(code if code>=0 else (0 if report.passed else 1))
