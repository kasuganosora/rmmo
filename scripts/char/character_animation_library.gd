extends RefCounted
const ArtPaths=preload("res://scripts/asset/art_paths.gd")
## Cached, offline-retargeted Quaternius clips. No source mannequin is loaded at runtime.
static var libraries:Dictionary={}
var clips:Dictionary={}
var tracks:Dictionary={}
func install(model:Node3D)->void:
	_load_library(model,ArtPaths.path("characters/animations/")+model.body_type+"_universal.res")
	_load_library(model,preload("res://scripts/util/json_util.gd").content_root()+"/assets/characters/animations/"+model.body_type+"_combat.res")
func _load_library(model:Node3D,path:String)->void:
	if not FileAccess.file_exists(path):return
	if not libraries.has(path):libraries[path]=load(path)
	var library:AnimationLibrary=libraries[path]
	for name in library.get_animation_list():
		var animation:=library.get_animation(name);clips[name]=animation
		var entries:Array=[]
		for track in range(animation.get_track_count()):
			var index:int=model.skeleton.find_bone(animation.track_get_path(track).get_subname(0))
			if index>=0:entries.append([track,index,animation.track_get_type(track)])
		tracks[name]=entries
func apply(model:Node3D,time:float)->bool:
	var key:String=model.animation_clip if not model.animation_clip.is_empty() else select_clip(model,model.action)
	if not clips.has(key):return false
	var animation:Animation=clips[key]
	if key=="dash_female":time*=1.25
	var sample:float=fposmod(time,animation.length) if animation.loop_mode==Animation.LOOP_LINEAR else clampf(time,0,animation.length)
	for entry in tracks[key]:
		if entry[2]==Animation.TYPE_ROTATION_3D:model.skeleton.set_bone_pose_rotation(entry[1],animation.rotation_track_interpolate(entry[0],sample))
		elif entry[2]==Animation.TYPE_POSITION_3D:model.skeleton.set_bone_pose_position(entry[1],animation.position_track_interpolate(entry[0],sample))
	if model.action=="idle":
		_relax_legs(model)
		_relax_arms(model)
		_relax_fingers(model)
	if model.action in ["idle","walk","dash"] and model.equipment.get("WeaponMain")!=null and int(model.equipment.WeaponMain)>0:
		_lower_weapon_wrist(model)
	return true

func _lower_weapon_wrist(model:Node3D)->void:
	# Keep the blade below the relaxed hand instead of pointing horizontally
	# through bystanders. Combat clips retain their authored wrist motion.
	var sk:Skeleton3D=model.skeleton
	var id:int=model.bones.handL
	var relative:Transform3D=model.rig.global_transform.affine_inverse()*sk.global_transform
	var pose:Basis=(relative*sk.get_bone_global_pose(id)).basis.orthonormalized()
	var parent:Basis=(relative*sk.get_bone_global_pose(sk.get_bone_parent(id))).basis.orthonormalized()
	sk.set_bone_pose_rotation(id,(parent.inverse()*Basis(Vector3.RIGHT,.65)*pose).get_rotation_quaternion())

const ATTACKS={"attack_jab":"空手 · 刺拳","attack_cross":"空手 · 直拳","attack_hook":"空手 · 勾拳","attack_sword_a":"持剑 · 斩击 A","attack_sword_b":"持剑 · 斩击 B","attack_sword_c":"持剑 · 斩击 C","attack_sword_combo":"持剑 · 连击","attack_sword_heavy":"持剑 · 重击连段","attack_sword_dash":"持剑 · 突进"}
const CASTS={"cast":"施法 · 标准","cast_quick":"施法 · 快速释放","cast_charge":"施法 · 蓄力释放"}
var attack_sequence:=0
func select_clip(model:Node3D,action:String,variant:String="",advance:bool=false)->String:
	if action=="attack":
		if ATTACKS.has(variant) and clips.has(variant):return variant
		var armed:bool=int(model.equipment.get("WeaponMain",0))>0 if model.equipment.get("WeaponMain")!=null else false
		if armed and model.equipment.get("WeaponStyle","")=="heavy":return "attack_sword_heavy"
		var choices:Array=["attack_sword_a","attack_sword_b","attack_sword_c"] if armed else ["attack_jab","attack_cross","attack_hook"]
		var choice:String=choices[attack_sequence%choices.size()]
		if advance:attack_sequence+=1
		return choice
	if action=="cast":return variant if CASTS.has(variant) and clips.has(variant) else "cast"
	if action=="dash" and model.body_type=="female" and clips.has("dash_female"):return "dash_female"
	return action
func duration(model:Node3D)->float:
	var key:String=model.animation_clip
	if clips.has(key):return clips[key].length/(1.25 if key=="dash_female" else 1.0)
	return float(model.Motion.DURATION.get(model.action,1.0))

func _relax_arms(model:Node3D)->void:
	# Rest-pose proportions differ from the mannequin. Align the arm chains
	# in character space rather than adding Euler offsets to retargeted bones.
	var sk:Skeleton3D=model.skeleton
	var relative:Transform3D=model.rig.global_transform.affine_inverse()*sk.global_transform
	for side in ["L","R"]:
		for pair in [["arm","forearm",.15,.015],["forearm","hand",.07,.10]]:
			var index:int=model.bones[pair[0]+side];var child:int=model.bones[pair[1]+side]
			var pose:Transform3D=relative*sk.get_bone_global_pose(index)
			var end:Vector3=(relative*sk.get_bone_global_pose(child)).origin
			var sign_x:float=signf(pose.origin.x)
			var target:=Vector3(sign_x*float(pair[2]),-1,float(pair[3])).normalized()
			var delta:=Quaternion((end-pose.origin).normalized(),target)
			var parent:int=sk.get_bone_parent(index)
			var parent_basis:Basis=(relative*sk.get_bone_global_pose(parent)).basis.orthonormalized()
			sk.set_bone_pose_rotation(index,(parent_basis.inverse()*Basis(delta)*pose.basis.orthonormalized()).get_rotation_quaternion())

func _relax_legs(model:Node3D)->void:
	# Neutral standing support under the hips, not the combat idle stance.
	var sk:Skeleton3D=model.skeleton
	var relative:Transform3D=model.rig.global_transform.affine_inverse()*sk.global_transform
	var floor_offset:=0.0
	for side in ["L","R"]:
		var foot:int=model.bones["foot"+side]
		var foot_basis:Basis=(relative*sk.get_bone_global_rest(foot)).basis.orthonormalized()
		for pair in [["thigh","shin"],["shin","foot"]]:
			var index:int=model.bones[pair[0]+side];var child:int=model.bones[pair[1]+side]
			var pose:Transform3D=relative*sk.get_bone_global_pose(index)
			var end:Vector3=(relative*sk.get_bone_global_pose(child)).origin
			var target:=Vector3(signf(pose.origin.x)*.025,-1,0).normalized()
			var rotation:=Quaternion((end-pose.origin).normalized(),target)
			var parent:Basis=(relative*sk.get_bone_global_pose(sk.get_bone_parent(index))).basis.orthonormalized()
			sk.set_bone_pose_rotation(index,(parent.inverse()*Basis(rotation)*pose.basis.orthonormalized()).get_rotation_quaternion())
		var parent:Basis=(relative*sk.get_bone_global_pose(sk.get_bone_parent(foot))).basis.orthonormalized()
		sk.set_bone_pose_rotation(foot,(parent.inverse()*foot_basis).get_rotation_quaternion())
		floor_offset+=(model.imported_rig.rest_positions["foot"+side].y-(relative*sk.get_bone_global_pose(foot)).origin.y)*.5
	var hips:int=model.bones.hips
	var parent_id:int=sk.get_bone_parent(hips)
	var parent_basis:Basis=(relative*sk.get_bone_global_pose(parent_id)).basis if parent_id>=0 else relative.basis
	sk.set_bone_pose_position(hips,sk.get_bone_pose_position(hips)+parent_basis.inverse()*Vector3.UP*floor_offset)

func _relax_fingers(model:Node3D)->void:
	var sk:Skeleton3D=model.skeleton
	var weapon=model.equipment.get("WeaponMain")
	for side in ["L","R"]:
		if side=="L" and weapon!=null and int(weapon)>0:continue
		var hand_name:String=sk.get_bone_name(model.bones["hand"+side])
		for bone in sk.get_bone_count():
			if sk.get_bone_name(bone).begins_with(hand_name) and bone!=model.bones["hand"+side]:
				var rest:Quaternion=sk.get_bone_rest(bone).basis.get_rotation_quaternion()
				sk.set_bone_pose_rotation(bone,rest.slerp(sk.get_bone_pose_rotation(bone),.25))
