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
	var reference:Dictionary={}
	for clip:StringName in library.get_animation_list():
		assert(motion.apply(body,clip,.5));reference[clip]=body.posed_points.duplicate()
	# Includes death -> idle and backward scrubbing within each action, not just
	# finite vertices or quaternion equality (which cannot detect axis winding).
	var largest:=0.0
	for clip:StringName in library.get_animation_list():
		var length:float=library.get_animation(clip).length
		for frame:int in 31:assert(motion.apply(body,clip,length*frame/30.0))
		for target:StringName in library.get_animation_list():
			assert(motion.apply(body,target,.5))
			for index:int in body.posed_points.size():largest=maxf(largest,reference[target][index].distance_to(body.posed_points[index]))
	assert(largest<.00001,"Animation history changes body surface")
	var seam_error:=0.0
	for clip:StringName in library.get_animation_list():
		var animation:Animation=library.get_animation(clip)
		if animation.loop_mode!=Animation.LOOP_LINEAR:continue
		assert(motion.apply(body,clip,0));var start:PackedVector3Array=body.posed_points.duplicate()
		assert(motion.apply(body,clip,animation.length-.001))
		for index:int in start.size():seam_error=maxf(seam_error,start[index].distance_to(body.posed_points[index]))
	assert(seam_error<.01,"Surface jumps near the loop seam despite identical endpoint matrices")
	# Same bone matrices with another equivalent Euler branch still need a solve.
	assert(motion.apply(body,"idle",.5))
	var original:PackedVector3Array=body.posed_points.duplicate()
	var branches:Dictionary={}
	for node:Dictionary in body.nodes:branches[node.name]=node.angles
	var twisted:Dictionary=branches.duplicate();var angles:Vector3=twisted.rForeArm
	angles.x+=TAU;twisted.rForeArm=angles
	assert(body.sync_final_pose(twisted))
	var difference:=0.0
	for index:int in original.size():difference=maxf(difference,original[index].distance_to(body.posed_points[index]))
	assert(difference>.001,"Negative control must change partial-axis deformation")
	assert(body.sync_final_pose(branches))
	for index:int in original.size():assert(original[index].distance_to(body.posed_points[index])<.00001)
	# Reject quaternion-only resources so stale generated assets cannot regress.
	var stale:AnimationLibrary=library.duplicate(true)
	for clip:StringName in stale.get_animation_list():
		var animation:Animation=stale.get_animation(clip)
		for track:int in range(animation.get_track_count()-1,-1,-1):
			if animation.track_get_type(track)==Animation.TYPE_VALUE:animation.remove_track(track)
	assert(not Motion.new().install(body.skeleton,stale))
	print("PASS history-independent surfaces: ",library.get_animation_list().size()*library.get_animation_list().size()," transitions + seeks, max_error_m=",largest," negative_control_m=",difference," loop_seam_m=",seam_error)
	body.free();quit()
