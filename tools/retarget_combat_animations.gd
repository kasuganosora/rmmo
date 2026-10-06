extends SceneTree
const ArtPaths=preload("res://scripts/asset/art_paths.gd")
## Offline retarget: world-space rest offsets, preserving destination bone lengths/weights.
const Model=preload("res://scripts/char/character_model_3d.gd")
var SOURCE:String = ArtPaths.path("characters/source_models/universal_animation_library/UAL1_Standard.glb")
const BASE_CLIPS={"idle":["Idle_Loop"],"walk":["Walk_Loop"],"dash":["Sprint_Loop"],"death":["Death01"],"cast":["Spell_Simple_Enter","Spell_Simple_Shoot","Spell_Simple_Exit"]}
var source:Node3D
var source_skeleton:Skeleton3D
var player:AnimationPlayer
func _initialize()->void:call_deferred("run")
func run()->void:
	if "--run-only" in OS.get_cmdline_user_args():
		retarget_set(SOURCE,{"dash_female":["Jog_Fwd_Loop"]});quit();return
	retarget_set(SOURCE,{"attack_jab":["Punch_Jab"],"attack_cross":["Punch_Cross"],"cast_quick":["Spell_Simple_Shoot"],"cast_charge":["Spell_Simple_Enter","Spell_Simple_Idle_Loop","Spell_Simple_Shoot","Spell_Simple_Exit"],"cast":["Spell_Simple_Enter","Spell_Simple_Shoot","Spell_Simple_Exit"],"idle":["Idle_Loop"],"dash_female":["Jog_Fwd_Loop"]})
	retarget_set(preload("res://scripts/util/json_util.gd").content_root()+"/assets/characters/source_models/universal_animation_library_2/UAL2_Standard.glb",{"attack_hook":["Melee_Hook","Melee_Hook_Rec"],"attack_sword_a":["Sword_Regular_A","Sword_Regular_A_Rec"],"attack_sword_b":["Sword_Regular_B","Sword_Regular_B_Rec"],"attack_sword_c":["Sword_Regular_C"],"attack_sword_combo":["Sword_Regular_Combo"],"attack_sword_heavy":["Sword_Heavy_Combo"],"attack_sword_dash":["Sword_Dash"]})
	quit()
func retarget_set(source_path:String,clip_map:Dictionary)->void:
	var doc:=GLTFDocument.new();var state:=GLTFState.new()
	assert(doc.append_from_file(source_path,state)==OK)
	source=doc.generate_scene(state);root.add_child(source)
	source_skeleton=source.find_children("*","Skeleton3D",true,false)[0]
	player=source.find_children("*","AnimationPlayer",true,false)[0]
	player.active=false
	print("Source clips: ",player.get_animation_list())
	var mapping:={"Hips":"pelvis","Spine":"spine_01","Spine1":"spine_02","Spine2":"spine_03","Neck":"neck_01","Head":"Head"}
	for side in ["Left","Right"]:
		var suffix:String="_l" if side=="Left" else "_r"
		for pair in [["Shoulder","clavicle"],["Arm","upperarm"],["ForeArm","lowerarm"],["Hand","hand"],["UpLeg","thigh"],["Leg","calf"],["Foot","foot"],["ToeBase","ball"]]:mapping[side+pair[0]]=pair[1]+suffix
		for finger in ["Thumb","Index","Middle","Ring","Pinky"]:
			for segment in range(1,4):mapping[side+"Hand"+finger+str(segment)]=finger.to_lower()+"_0"+str(segment)+suffix
	for gender in ["male","female"]:
		var model:=Model.new();root.add_child(model);model.configure(gender,{},{});model.set_process(false)
		model.skeleton.reset_bone_poses()
		var sk:Skeleton3D=model.skeleton
		var relative:Transform3D=model.rig.global_transform.affine_inverse()*sk.global_transform
		var pairs:Dictionary={}
		for i in range(sk.get_bone_count()):
			var key:=sk.get_bone_name(i).trim_prefix("mixamorig_")
			if mapping.has(key):
				var j:=source_skeleton.find_bone(mapping[key]);assert(j>=0,key);pairs[i]=j
		var hip:int=sk.find_bone("mixamorig_Hips");var src_hip:int=pairs[hip]
		var source_rest:Transform3D=source_skeleton.global_transform*source_skeleton.get_bone_global_rest(src_hip)
		var target_rest:Transform3D=relative*sk.get_bone_global_rest(hip)
		var ratio:float=target_rest.origin.y/source_rest.origin.y
		var feet:Array[int]=[]
		var src_floor:=INF;var dst_floor:=INF
		for i in pairs:
			if sk.get_bone_name(i).ends_with("Foot") or sk.get_bone_name(i).ends_with("ToeBase"):
				feet.append(i)
				src_floor=minf(src_floor,(source_skeleton.global_transform*source_skeleton.get_bone_global_rest(pairs[i])).origin.y)
				dst_floor=minf(dst_floor,(relative*sk.get_bone_global_rest(i)).origin.y)
		var output:String=preload("res://scripts/util/json_util.gd").content_root()+"/assets/characters/animations/"+gender+"_combat.res"
		var library:AnimationLibrary=load(output) if FileAccess.file_exists(output) else AnimationLibrary.new()
		for action in clip_map:
			var animation:=Animation.new();var tracks:Dictionary={}
			for i in pairs:
				var track:=animation.add_track(Animation.TYPE_ROTATION_3D);animation.track_set_path(track,NodePath("Skeleton3D:"+sk.get_bone_name(i)));tracks[i]=track
			var position_track:=animation.add_track(Animation.TYPE_POSITION_3D);animation.track_set_path(position_track,NodePath("Skeleton3D:"+sk.get_bone_name(hip)))
			var offset:=0.0
			for clip in clip_map[action]:
				var original:=player.get_animation(clip);assert(original!=null)
				var count:=int(round(original.length*30))
				for frame in range(count+1):
					if offset>0 and frame==0:continue
					var time:=original.length*frame/count
					source_skeleton.reset_bone_poses()
					for track in range(original.get_track_count()):
						var path:=original.track_get_path(track)
						if path.get_subname_count()==0:continue
						var bone:=source_skeleton.find_bone(path.get_subname(0))
						if bone<0:continue
						match original.track_get_type(track):
							Animation.TYPE_ROTATION_3D:source_skeleton.set_bone_pose_rotation(bone,original.rotation_track_interpolate(track,time))
							Animation.TYPE_POSITION_3D:source_skeleton.set_bone_pose_position(bone,original.position_track_interpolate(track,time))
							Animation.TYPE_SCALE_3D:source_skeleton.set_bone_pose_scale(bone,original.scale_track_interpolate(track,time))
					sk.reset_bone_poses()
					# Skeleton bone indices are parent-first in the imported destination.
					for i in range(sk.get_bone_count()):
						if not pairs.has(i):continue
						var j:int=pairs[i]
						var src_rest:Basis=(source_skeleton.global_transform*source_skeleton.get_bone_global_rest(j)).basis.orthonormalized()
						var src_pose:Basis=(source_skeleton.global_transform*source_skeleton.get_bone_global_pose(j)).basis.orthonormalized()
						var dst_rest:Basis=(relative*sk.get_bone_global_rest(i)).basis.orthonormalized()
						var desired:Basis=src_pose*src_rest.inverse()*dst_rest
						var parent:=sk.get_bone_parent(i)
						var parent_transform:Transform3D=relative if parent<0 else relative*sk.get_bone_global_pose(parent)
						var rotation:Quaternion=(parent_transform.basis.orthonormalized().inverse()*desired).get_rotation_quaternion().normalized()
						sk.set_bone_pose_rotation(i,rotation)
						animation.rotation_track_insert_key(tracks[i],offset+time,rotation)
						if i==hip:
							var src_position:Vector3=(source_skeleton.global_transform*source_skeleton.get_bone_global_pose(j)).origin
							var position:Vector3=parent_transform.affine_inverse()*(target_rest.origin+(src_position-source_rest.origin)*ratio)
							sk.set_bone_pose_position(i,position)
							animation.position_track_insert_key(position_track,offset+time,position)
					if action!="death":
						# Preserve the original support/airborne height despite different limb proportions.
						var src_low:=INF;var dst_low:=INF
						for i in feet:
							src_low=minf(src_low,(source_skeleton.global_transform*source_skeleton.get_bone_global_pose(pairs[i])).origin.y)
							dst_low=minf(dst_low,(relative*sk.get_bone_global_pose(i)).origin.y)
						var correction:float=dst_floor+(src_low-src_floor)*ratio-dst_low
						var parent:=sk.get_bone_parent(hip)
						var parent_basis:Basis=relative.basis if parent<0 else (relative*sk.get_bone_global_pose(parent)).basis
						var position:Vector3=sk.get_bone_pose_position(hip)+parent_basis.inverse()*Vector3(0,correction,0)
						animation.position_track_insert_key(position_track,offset+time,position)
				offset+=original.length
			animation.length=offset
			if action in ["idle","walk","dash","dash_female"]:
				animation.loop_mode=Animation.LOOP_LINEAR
				# Source loops have small endpoint differences. Distribute the closing
				# correction over 0.1 s instead of snapping at the cycle boundary.
				for track in range(animation.get_track_count()):
					var first=animation.track_get_key_value(track,0)
					for key in range(animation.track_get_key_count(track)):
						var weight:=smoothstep(offset-.1,offset,animation.track_get_key_time(track,key))
						if weight<=0:continue
						var value=animation.track_get_key_value(track,key)
						animation.track_set_key_value(track,key,value.slerp(first,weight) if value is Quaternion else value.lerp(first,weight))
			if action=="dash_female":refine_run(animation,model)
			if library.has_animation(action):library.remove_animation(action)
			library.add_animation(action,animation)
			print(gender," ",action," ",offset,"s, ",pairs.size()," bones")
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		assert(ResourceSaver.save(library,output)==OK)
		model.free()
	source.free()


# Bake the jog correction offline. Keep UAL cycle timing, but solve the target
# leg chains after reducing stride/flight so flattening the hips cannot bury feet.
func refine_run(animation:Animation,model:Node3D)->void:
	var sk:Skeleton3D=model.skeleton
	var relative:Transform3D=model.rig.global_transform.affine_inverse()*sk.global_transform
	var hip:int=model.bones.hips
	var original:Animation=animation.duplicate()
	var ids:Dictionary={};var hip_track:=-1
	for track in range(animation.get_track_count()):
		ids[track]=sk.find_bone(animation.track_get_path(track).get_subname(0))
		if animation.track_get_type(track)==Animation.TYPE_POSITION_3D:hip_track=track
	var count:=animation.track_get_key_count(hip_track)
	for key in range(count):
		apply_sample(original,sk,ids,hip_track,key)
		var phase:float=animation.track_get_key_time(hip_track,key)/animation.length
		# Two small rises per stride; the source's deep compression/large flight
		# is unsuitable for this character's everyday run.
		var rest:Vector3=model.imported_rig.rest_positions.hips
		var hips:=rest+Vector3(.008*sin(TAU*phase),-.20-.022*cos(2*TAU*(phase-.125)),0)
		var parent:int=sk.get_bone_parent(hip)
		var parent_transform:Transform3D=relative if parent<0 else relative*sk.get_bone_global_pose(parent)
		sk.set_bone_pose_position(hip,parent_transform.affine_inverse()*hips)
		for track in ids:
			if track==hip_track:continue
			var bone:int=ids[track];var name:=sk.get_bone_name(bone)
			if bone==hip or "Spine" in name or "Neck" in name or name.ends_with("Head"):
				var rest_rotation:=sk.get_bone_rest(bone).basis.get_rotation_quaternion()
				sk.set_bone_pose_rotation(bone,rest_rotation.slerp(sk.get_bone_pose_rotation(bone),.30))
		# Forward is +Z in character space. Tilt from the pelvis, then solve
		# legs back to their contact targets rather than tipping the whole rig.
		var hip_pose:Transform3D=relative*sk.get_bone_global_pose(hip)
		var lean:Basis=Basis(Vector3.RIGHT,.18)*hip_pose.basis.orthonormalized()
		sk.set_bone_pose_rotation(hip,(parent_transform.basis.orthonormalized().inverse()*lean).get_rotation_quaternion())
		for side in ["L","R"]:
			var leg_phase:float=fposmod(phase+(0.5 if side=="L" else 0.0),1.0)
			var lift:=0.0;var stride:=0.0;var pitch:=0.0
			if leg_phase<.38:
				# Constant-speed support, followed by a short flight interval.
				stride=lerpf(.60,-.65,leg_phase/.38)
			else:
				var u:float=(leg_phase-.38)/.62
				var v:float=1.0-u
				# Matching contact velocities avoids the foot snapping backwards.
				var tangent:float=(1.25/.38)*.62/3.0
				stride=v*v*v*(-.65)+3*v*v*u*(-.65-tangent)+3*v*u*u*(.60+tangent)+u*u*u*.60
				lift=.38*pow(sin(PI*u),2)
				pitch=.42*sin(TAU*u)*pow(sin(PI*u),2)
			model.imported_rig.plant_leg(model,side,Vector3(0,lift,stride),pitch)
			# Alternate with the opposite leg. Relaxed elbows, sagittal swing,
			# a little clearance from the torso, no crossing of the centerline.
			var swing:float=-.08-.38*cos(TAU*(phase+(0.5 if side=="L" else 0.0)))
			align_limb(sk,relative,model.bones["arm"+side],model.bones["forearm"+side],Vector3(-.10 if side=="L" else .10,-cos(swing),sin(swing)))
			var fore_angle:float=swing+1.45+.06*sin(TAU*phase)
			align_limb(sk,relative,model.bones["forearm"+side],model.bones["hand"+side],Vector3(.025 if side=="L" else -.025,-cos(fore_angle),sin(fore_angle)))
		for track in ids:
			animation.track_set_key_value(track,key,sk.get_bone_pose_position(hip) if track==hip_track else sk.get_bone_pose_rotation(ids[track]))
	# Rig-space support distance per second of source clip playback.
	animation.set_meta("ground_speed",1.25/(.38*animation.length))
	# Exactly matching endpoint, including all corrected chains.
	for track in ids:animation.track_set_key_value(track,count-1,animation.track_get_key_value(track,0))

func apply_sample(animation:Animation,sk:Skeleton3D,ids:Dictionary,hip_track:int,key:int)->void:
	sk.reset_bone_poses()
	for track in ids:
		if track==hip_track:sk.set_bone_pose_position(ids[track],animation.track_get_key_value(track,key))
		else:sk.set_bone_pose_rotation(ids[track],animation.track_get_key_value(track,key))

func align_limb(sk:Skeleton3D,relative:Transform3D,bone:int,child:int,direction:Vector3)->void:
	var start:Transform3D=relative*sk.get_bone_global_pose(bone)
	var end:Vector3=(relative*sk.get_bone_global_pose(child)).origin
	var delta:=Quaternion((end-start.origin).normalized(),direction.normalized())
	var parent_basis:Basis=(relative*sk.get_bone_global_pose(sk.get_bone_parent(bone))).basis.orthonormalized()
	sk.set_bone_pose_rotation(bone,(parent_basis.inverse()*Basis(delta)*start.basis.orthonormalized()).get_rotation_quaternion().normalized())
