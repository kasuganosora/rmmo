extends SceneTree
const Body=preload("res://scripts/char/female_axis_body.gd")
const Motion=preload("res://scripts/char/character_axis_animation.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var body:=Body.new();root.add_child(body);body.initialize();assert(body.enable_compute())
	var motion:=Motion.new()
	var library:AnimationLibrary=load(Art.path("characters/animations/female_base_v2_universal.res"))
	assert(motion.install(body.skeleton,library))
	var report:Array=[];var flight_samples:=0
	var anchor:=Vector3(12,3,-7);body.position=anchor
	for clip:StringName in library.get_animation_list():
		var worst_before:=INF;var worst_after:=INF;var largest_lift:=0.0
		var animation:Animation=library.get_animation(clip)
		for frame:int in 61:
			var time:float=animation.length*frame/60.0
			motion.support_enabled=false;assert(motion.apply(body,clip,time))
			var surface:PackedVector3Array=body.posed_points.duplicate()
			var rotations:Array[Quaternion]=[]
			for bone:int in body.skeleton.get_bone_count():rotations.append(body.skeleton.get_bone_pose_rotation(bone))
			var raw:Vector3=motion.visual_offset;var low:=INF
			for point:Vector3 in surface:low=minf(low,point.y+raw.y)
			motion.support_enabled=true;assert(motion.apply(body,clip,time))
			assert(surface==body.posed_points,"Ground support must not alter skinning")
			for bone:int in rotations.size():assert(rotations[bone].is_equal_approx(body.skeleton.get_bone_pose_rotation(bone)),"Support changed the authored posture")
			assert(body.position==anchor,"Support moved the gameplay/actor anchor")
			assert(motion.visual_offset.x==raw.x and motion.visual_offset.z==raw.z)
			var after:float=low+motion.support_adjustment
			assert(after>=-.000001 and motion.support_adjustment>=0)
			if low>0.005:
				assert(motion.visual_offset==raw,"Airborne motion was snapped to the floor");flight_samples+=1
			worst_before=minf(worst_before,low);worst_after=minf(worst_after,after);largest_lift=maxf(largest_lift,motion.support_adjustment)
		report.append({"clip":clip,"samples":61,"lowest_before_m":worst_before,"lowest_after_m":worst_after,"largest_visual_lift_m":largest_lift})
		print("SUPPORT ",clip," before=",worst_before," after=",worst_after," lift=",largest_lift)
	assert(flight_samples>0,"Negative control needs genuine airborne frames")
	motion.support_height=.35;assert(motion.apply(body,"death",library.get_animation("death").length))
	var raised_min:=INF
	for point:Vector3 in body.posed_points:raised_min=minf(raised_min,point.y+motion.visual_offset.y)
	assert(raised_min>=.35-.000001,"Support height was hardcoded to world zero")
	var folder:String=Art.review_path("character_3d/axis_support_01");DirAccess.make_dir_recursive_absolute(folder)
	var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"clips":report,"airborne_samples_unchanged":flight_samples,"raised_support_minimum_m":raised_min},"\t"));file.close()
	print("PASS 305 supported samples, unchanged pose and actor anchor; preserved flight samples=",flight_samples)
	body.free();quit()
