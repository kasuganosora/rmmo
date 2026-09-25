extends SceneTree
const ArtPaths=preload("res://scripts/asset/art_paths.gd")
## Offline retarget: world-space rest offsets, preserving destination bone lengths/weights.
const Model=preload("res://scripts/char/character_model_3d.gd")
var SOURCE:String = ArtPaths.path("characters/source_models/universal_animation_library/UAL1_Standard.glb")
const CLIPS={"idle":["Idle_Loop"],"walk":["Walk_Loop"],"dash":["Sprint_Loop"],"death":["Death01"],"cast":["Spell_Simple_Enter","Spell_Simple_Shoot","Spell_Simple_Exit"]}
var source:Node3D
var source_skeleton:Skeleton3D
var player:AnimationPlayer
func _initialize()->void:call_deferred("run")
func run()->void:
	var doc:=GLTFDocument.new();var state:=GLTFState.new()
	assert(doc.append_from_file(SOURCE,state)==OK)
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
		var library:=AnimationLibrary.new()
		for action in CLIPS:
			var animation:=Animation.new();var tracks:Dictionary={}
			for i in pairs:
				var track:=animation.add_track(Animation.TYPE_ROTATION_3D);animation.track_set_path(track,NodePath("Skeleton3D:"+sk.get_bone_name(i)));tracks[i]=track
			var position_track:=animation.add_track(Animation.TYPE_POSITION_3D);animation.track_set_path(position_track,NodePath("Skeleton3D:"+sk.get_bone_name(hip)))
			var offset:=0.0
			for clip in CLIPS[action]:
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
			if action in ["idle","walk","dash"]:
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
			library.add_animation(action,animation)
			print(gender," ",action," ",offset,"s, ",pairs.size()," bones")
		var output:String=ArtPaths.path("characters/animations/")+gender+"_universal.res"
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		assert(ResourceSaver.save(library,output)==OK)
		model.free()
	source.free();quit()
