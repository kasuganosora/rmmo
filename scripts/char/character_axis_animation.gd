extends RefCounted
const ExistingMotion=preload("res://scripts/char/character_animation_library.gd")
const AxisBody=preload("res://scripts/char/female_axis_body.gd")
## Rotation-only animation for the axis-weight body. The caller applies
## visual_offset to its visual root, never to gameplay/world movement.
var library:AnimationLibrary
var visual_offset:=Vector3.ZERO
## Flat support in the visual root's local, metre-based coordinate system.
## The world/terrain owner supplies the anchor; this does not move that owner.
var support_enabled:=true
var support_height:=0.0
var authored_offset:=Vector3.ZERO
var support_adjustment:=0.0
var tracks:Dictionary={}
var skeleton_id:int=0
func install(skeleton:Skeleton3D,source:AnimationLibrary)->bool:
	var bindings:Dictionary={}
	if source==null:return false
	for clip:StringName in source.get_animation_list():
		var animation:Animation=source.get_animation(clip)
		if animation.length<=0:return false
		var bound:Array=[]
		var rotations:Dictionary={};var references:Dictionary={}
		for track:int in animation.get_track_count():
			if animation.track_get_key_count(track)==0:return false
			var path:NodePath=animation.track_get_path(track)
			if animation.track_get_type(track)==Animation.TYPE_VALUE and path.get_name_count()==1 and path.get_name(0)=="AxisAngles" and path.get_subname_count()==1:
				if skeleton.find_bone(path.get_subname(0))<0:return false
				var key:String=path.get_subname(0)
				if references.has(key):return false
				references[key]=true
				for index:int in animation.track_get_key_count(track):
					var value=animation.track_get_key_value(track,index)
					if not value is Vector3 or not value.is_finite():return false
				bound.append(-2);continue
			if animation.track_get_type(track)==Animation.TYPE_POSITION_3D and path==NodePath("VisualRoot:position"):
				bound.append(-1);continue
			if animation.track_get_type(track)!=Animation.TYPE_ROTATION_3D or path.get_subname_count()!=1:return false
			var bone:int=skeleton.find_bone(path.get_subname(0))
			if bone<0:return false
			rotations[String(path.get_subname(0))]=true
			bound.append(bone)
		if rotations.is_empty() or rotations.size()!=references.size():return false
		for key:String in rotations:
			if not references.has(key):return false
		bindings[clip]=bound
	library=source;tracks=bindings;skeleton_id=skeleton.get_instance_id()
	return true
func apply(body:Node3D,clip:StringName,time:float)->bool:
	if library==null or not tracks.has(clip) or not is_finite(time) or not is_finite(support_height) or body.skeleton.get_instance_id()!=skeleton_id:return false
	var animation:Animation=library.get_animation(clip)
	var sample:float=fposmod(time,animation.length) if animation.loop_mode==Animation.LOOP_LINEAR else clampf(time,0,animation.length)
	# Reset unmapped carpals, face and other helper joints to the source rest.
	# Do not reset mesh buffers or re-create body/material instances.
	body.skeleton.reset_bone_poses()
	visual_offset=Vector3.ZERO
	var references:Dictionary={}
	for track:int in tracks[clip].size():
		var bone:int=tracks[clip][track]
		if bone==-2:references[String(animation.track_get_path(track).get_subname(0))]=animation.value_track_interpolate(track,sample)
		elif bone==-1:visual_offset=animation.position_track_interpolate(track,sample)
		else:body.skeleton.set_bone_pose_rotation(bone,animation.rotation_track_interpolate(track,sample))
	# Unmapped helper joints are at rest and must not retain old branch windings.
	for node:Dictionary in body.nodes:
		if not references.has(node.name):references[node.name]=Vector3.ZERO
	if clip==&"idle":_relax_idle(body.skeleton)
	var rest_weight:=0.0
	if clip==&"lie":rest_weight=1.0
	elif clip==&"get_up":rest_weight=1.0-smoothstep(0,.25,sample)
	elif clip==&"lie_down":rest_weight=smoothstep(animation.length-.25,animation.length,sample)
	if rest_weight>0:
		# Reuse the previously checked head/palm-up resting pose. The source
		# get-up starts with hands raised for recovery, not relaxed sleeping.
		for node:Dictionary in body.nodes:
			var angles:Vector3=AxisBody.POSES.lie_relaxed.get(node.name,Vector3.ZERO)*PI/180.0
			var bone:int=node.skeleton_index
			var rotation:Quaternion=(body.skeleton.get_bone_rest(bone).basis*AxisBody.ordered_basis(angles,AxisBody.ORDERS[node.order])).get_rotation_quaternion()
			body.skeleton.set_bone_pose_rotation(bone,body.skeleton.get_bone_pose_rotation(bone).slerp(rotation,rest_weight))
			references[node.name]=(references.get(node.name,Vector3.ZERO) as Vector3).lerp(angles,rest_weight)
	references.merge(body.apply_expression_bones(),true)
	if not body.sync_final_pose(references):return false
	if rest_weight>0:
		var lowest:float=body.surface_min_y
		visual_offset=visual_offset.lerp(Vector3(0,support_height-lowest-body.root_offset.y,0),rest_weight)
	visual_offset=apply_support(body,visual_offset)
	return true

func apply_support(body:Node3D,offset:Vector3)->Vector3:
	authored_offset=offset
	support_adjustment=0.0
	if support_enabled:
		var lowest:float=body.surface_min_y
		# Only lift a penetrating surface. Snapping every frame to the floor
		# would erase genuine airborne phases and change the source action.
		support_adjustment=maxf(0.0,support_height-lowest-body.root_offset.y-offset.y)
		offset.y+=support_adjustment
	return offset

func _relax_idle(sk:Skeleton3D)->void:
	# Reuse the approved old renderer's natural idle direction/finger policy.
	# This is animation styling, not a substitute for cloth contact constraints.
	for side:String in ["r","l"]:
		var foot:int=sk.find_bone(side+"Foot")
		var before:float=sk.get_bone_global_pose(foot).origin.y
		for pair:Array in [["Thigh","Shin"],["Shin","Foot"]]:
			var bone:int=sk.find_bone(side+pair[0]);var child:int=sk.find_bone(side+pair[1])
			ExistingMotion.align_bone_toward(sk,bone,child,Vector3(signf(sk.get_bone_global_pose(bone).origin.x)*.025,-1,0))
		var parent:Basis=sk.get_bone_global_pose(sk.get_bone_parent(foot)).basis.orthonormalized()
		sk.set_bone_pose_rotation(foot,(parent.inverse()*sk.get_bone_global_rest(foot).basis.orthonormalized()).get_rotation_quaternion())
		visual_offset.y+=(before-sk.get_bone_global_pose(foot).origin.y)*.5
		for pair:Array in [["Shldr","ForeArm",.15,.015],["ForeArm","Hand",.07,.10]]:
			var bone:int=sk.find_bone(side+pair[0]);var child:int=sk.find_bone(side+pair[1])
			ExistingMotion.align_bone_toward(sk,bone,child,Vector3(signf(sk.get_bone_global_pose(bone).origin.x)*float(pair[2]),-1,float(pair[3])))
		for finger:String in ["Thumb","Index","Mid","Ring","Pinky"]:
			for segment:int in range(1,4):
				var bone:int=sk.find_bone(side+finger+str(segment))
				sk.set_bone_pose_rotation(bone,sk.get_bone_rest(bone).basis.get_rotation_quaternion().slerp(sk.get_bone_pose_rotation(bone),.25))

func reference_position(skeleton:Skeleton3D,clip:StringName,bone_name:String)->Vector3:
	# Sample authored FK without posing the visible body or emitting surface updates.
	var animation:Animation=library.get_animation(clip)
	var poses:Array[Transform3D]=[]
	for i in skeleton.get_bone_count():poses.append(skeleton.get_bone_rest(i))
	var offset:=Vector3.ZERO
	for track in animation.get_track_count():
		var path:NodePath=animation.track_get_path(track)
		if animation.track_get_type(track)==Animation.TYPE_ROTATION_3D:
			var index:int=skeleton.find_bone(path.get_subname(0))
			poses[index].basis=Basis(animation.rotation_track_interpolate(track,0))
		elif animation.track_get_type(track)==Animation.TYPE_POSITION_3D and path==NodePath("VisualRoot:position"):
			offset=animation.position_track_interpolate(track,0)
	var index:int=skeleton.find_bone(bone_name)
	var result:Transform3D=poses[index]
	index=skeleton.get_bone_parent(index)
	while index>=0:
		result=poses[index]*result;index=skeleton.get_bone_parent(index)
	return result.origin+offset
