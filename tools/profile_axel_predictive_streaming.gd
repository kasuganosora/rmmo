extends "res://tools/profile_axel_white_streaming.gd"
## Same white geometry entry/residency/exit as the established probe. The sole
## A/B switch is the production predictor: old building box vs bounded corridor.
const Approach=preload("res://scripts/world3d/approach_preparation.gd")
var predictor:=Approach.new()
var intended_velocity:=Vector3.ZERO
var intended_route:=PackedVector3Array()
var next_prediction_msec:=0
var prediction_samples:Array=[]
var route_corner:=Vector3.ZERO
var maximum_prediction_us:=0

func _initialize()->void:
	Approach.predictive_enabled=not "--legacy-approach" in OS.get_cmdline_user_args()
	super._initialize()

func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_predictive_streaming.gd"]=FileAccess.get_sha256("res://tools/profile_axel_predictive_streaming.gd")
	return result

func tick_geometry()->void:
	if Time.get_ticks_msec()>=next_prediction_msec:
		next_prediction_msec=Time.get_ticks_msec()+250
		var queue:Node=mesh_map.get_node("DeferredAssets")
		var began:=Time.get_ticks_usec()
		predictor.update(queue,position,intended_velocity,intended_route)
		maximum_prediction_us=maxi(maximum_prediction_us,Time.get_ticks_usec()-began)
		var footprint:=AABB(Vector3(position.x-2,-100000,position.z-2),Vector3(4,200000,4))
		prediction_samples.append({"phase":phase,"at_ms":(Time.get_ticks_usec()-self.began)/1000.,"pending_at_feet":queue._has_pending_in_clip(footprint),"tickets":predictor.profile.tickets,"jobs":queue._jobs.size(),"bytes":queue._admission.reserved_bytes})
	super.tick_geometry()

func segment(label:String,destination:Vector3,seconds:float,following:PackedVector3Array=PackedVector3Array())->void:
	intended_velocity=(destination-position)/maxf(seconds,.001)
	intended_route=PackedVector3Array([destination]);intended_route.append_array(following)
	# Give intent to the same four-Hz production update before the first step.
	next_prediction_msec=0
	await super.leg(label,destination,seconds)
	intended_velocity=Vector3.ZERO;intended_route.clear()

func leg(label:String,destination:Vector3,seconds:float)->void:
	if label=="white_walk_outbound":
		route_corner=Vector3(destination.x,position.y,position.z)
		await segment(label+"_straight",route_corner,position.distance_to(route_corner)/6.,PackedVector3Array([destination]))
		await segment(label+"_turn",destination,position.distance_to(destination)/6.)
	elif label=="white_walk_return":
		await segment(label+"_straight",route_corner,position.distance_to(route_corner)/6.,PackedVector3Array([destination]))
		await segment(label+"_turn",destination,position.distance_to(destination)/6.)
	else:await segment(label,destination,seconds)

func traverse()->void:
	await super.traverse()
	report.prediction={"mode":"corridor" if Approach.predictive_enabled else "legacy_building_box","profile":predictor.profile.duplicate(),"max_update_us":maximum_prediction_us,"samples":prediction_samples,"sample_interval_ms":250,"contract":"controlled camera/focus with known corner route; sample pending source geometry at feet, not physical/gameplay stall time"}
	predictor.release()
