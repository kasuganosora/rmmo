extends RefCounted
## New body adapter for the shared CharacterModel3D entry, never a second actor.
const Body=preload("res://scripts/char/female_axis_body.gd")
const Motion=preload("res://scripts/char/character_axis_animation.gd")
const Wardrobe=preload("res://scripts/char/character_surface_wardrobe.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
const MAP={"hips":"hip","spine":"abdomen","chest":"abdomen2","upper_chest":"chest","neck":"neck","head":"head"}
var body:Node3D
var wardrobe:Node3D
var cloth=preload("res://scripts/char/character_runtime_cloth.gd").new()
var weapon:Node3D
var shield:Node3D
var twohand=preload("res://scripts/char/character_axis_twohand.gd").new()
var seat=preload("res://scripts/char/character_axis_seat.gd").new()
var seat_cloth_revision:=0
var pending_cloth_delta:=0.0
var cloth_ik_revision:=0
var attack_sequence:=0
var hair:Node3D
var animations:=Motion.new()
var ground_pose=preload("res://scripts/char/character_ground_pose_preparer.gd").new()
var ground_actions=preload("res://scripts/char/character_ground_action_preparer.gd").new()
var last_error:=""
var head_vertices:=PackedInt32Array()
var reported_unsupported:Dictionary={}
static func available()->bool:
	for path:String in ["characters/base/female_base_v2/female_axis_rig.json","characters/base/female_base_v2/female_display_topology.json","characters/animations/female_base_v2_universal.res"]:
		if not FileAccess.file_exists(Art.path(path)):return false
	return true
func install(model:Node3D)->bool:
	var path:String=Art.path("characters/animations/female_base_v2_universal.res")
	if not FileAccess.file_exists(path):last_error="Missing axis animation library";return false
	body=Body.new();model.rig.add_child(body);body.initialize();body.enable_compute()
	if not body.set_shape_values(Body.Shapes.normalize(model.appearance.get("body_shapes",{}))):
		last_error="Missing/incompatible identity shape data";body.free();body=null;return false
	var library:AnimationLibrary=load(path).duplicate()
	var combat_path:String=Art.path("characters/animations/female_base_v2_combat.res")
	if FileAccess.file_exists(combat_path):
		var combat:AnimationLibrary=load(combat_path)
		for clip:StringName in combat.get_animation_list():library.add_animation(clip,combat.get_animation(clip))
	var recovery_path:String=Art.path("characters/animations/female_base_v2_recovery.res")
	if FileAccess.file_exists(recovery_path):
		var recovery:AnimationLibrary=load(recovery_path)
		for clip:StringName in recovery.get_animation_list():library.add_animation(clip,recovery.get_animation(clip))
	var chair_path:String=Art.path("characters/animations/female_base_v2_chair.res")
	if FileAccess.file_exists(chair_path):
		var chair:AnimationLibrary=load(chair_path)
		for clip:StringName in chair.get_animation_list():library.add_animation(clip,chair.get_animation(clip))
	if not animations.install(body.skeleton,library):
		last_error="Axis animation library is incompatible; regenerate --axis-body";body.free();body=null;return false
	model.skeleton.free();model.skeleton=body.skeleton
	for key:String in MAP:model.bones[key]=model.skeleton.find_bone(MAP[key])
	for side:String in ["L","R"]:
		for pair:Array in [["arm","Shldr"],["forearm","ForeArm"],["hand","Hand"],["thigh","Thigh"],["shin","Shin"],["foot","Foot"]]:
			model.bones[pair[0]+side]=model.skeleton.find_bone(side.to_lower()+pair[1])
	wardrobe=Wardrobe.new();body.add_child(wardrobe);wardrobe.configure(body)
	cloth.configure(body,wardrobe)
	weapon=preload("res://scripts/char/character_axis_weapon.gd").new();body.add_child(weapon);weapon.configure(body,library)
	shield=preload("res://scripts/char/character_axis_shield.gd").new();body.add_child(shield);shield.configure(body)
	twohand.configure(body,weapon);twohand.bridge.pose_solved.connect(_after_weapon_ik)
	seat.configure(body);seat.bridge.pose_solved.connect(_after_seat_ik)
	body.set_colors(model.appearance)
	hair=preload("res://scripts/char/character_source_hair.gd").new();body.add_child(hair);hair.configure_body(body)
	if not hair.apply(model):push_warning(hair.error)
	for index:int in body.rest_points.size():
		if body.rest_points[index].y>=body.rests.head.origin.y:head_vertices.append(index)
	return true
func head_top(direction:Vector3)->float:
	var top:float=-INF
	for index:int in head_vertices:top=maxf(top,(body.global_transform*(body.posed_points[index]+body.root_offset)).dot(direction))
	if hair!=null:top=maxf(top,hair.projected_top(direction))
	return top
func update_appearance(model:Node3D)->bool:
	var previous_shapes:Dictionary=body.shape_values.duplicate()
	if not body.set_shape_values(Body.Shapes.normalize(model.appearance.get("body_shapes",{}))):
		last_error="Identity shape update failed";push_error(last_error);return false
	model.rig.position=animations.apply_support(body,animations.authored_offset)
	body.set_colors(model.appearance)
	if previous_shapes!=body.shape_values:cloth.invalidate()
	hair.refit_body()
	if not hair.apply(model):push_warning(hair.error)
	return true
func set_equipment(parts:Dictionary)->bool:
	var recipe:Variant=parts.get("SurfaceEquipment",{})
	if not recipe is Dictionary:last_error="SurfaceEquipment must be a dictionary";return false
	var cloth_slots:Variant=parts.get("SurfaceClothSlots",[])
	if not cloth_slots is Array:last_error="SurfaceClothSlots must be an array";return false
	for slot in cloth_slots:
		if not slot is String:last_error="SurfaceClothSlots entries must be strings";return false
	if not wardrobe.set_equipment(recipe):last_error="Invalid surface equipment recipe";return false
	cloth.reconcile(cloth_slots)
	if str(parts.get("WeaponMainItem",""))!="great_club" or parts.get("WeaponMain")==null or int(parts.get("WeaponMain",0))<=0:twohand.cancel(true)
	weapon.set_equipment(parts)
	shield.set_equipment(parts)
	last_error="";return true
func pose(model:Node3D,time:float)->bool:
	var clip:StringName=model.animation_clip if not model.animation_clip.is_empty() else model.action
	if not animations.apply(body,clip,time):last_error="Unsupported axis action: "+String(clip);return false
	weapon.apply_grip(true)
	model.rig.position=model.rig.basis*animations.visual_offset
	last_error="";return true
func sync_blend(model:Node3D,from:Dictionary,weight:float)->bool:
	var references:Dictionary={}
	for node:Dictionary in body.nodes:
		references[node.name]=(from.get(node.name,node.angles) as Vector3).lerp(node.angles,weight)
	if not body.sync_final_pose(references):last_error=body.pose_sync_error;return false
	weapon.apply_grip(false)
	model.rig.position=animations.apply_support(body,model.rig.position)
	return true
func duration(clip:StringName)->float:
	return animations.library.get_animation(clip).length if animations.library.has_animation(clip) else 0.0
## Returns a prepared static clip. The rest-action controller must provide and
## validate entry/exit transitions before exposing it as a gameplay action.
func prepare_ground_pose()->Animation:
	var requested:Dictionary=body.shape_values.duplicate(true)
	var prepared:Animation=await ground_pose.prepare(body,requested)
	if not is_instance_valid(body):return null
	if body.shape_values!=requested:
		last_error="Body shape changed during ground pose preparation";return null
	if prepared==null:last_error=ground_pose.error
	return prepared
func prepare_ground_actions()->AnimationLibrary:
	if not supports("get_up"):
		last_error="Missing ground recovery animation";return null
	var requested:Dictionary=body.shape_values.duplicate(true)
	var seated:Animation=await prepare_ground_pose()
	if seated==null or not is_instance_valid(body):return null
	var result:AnimationLibrary=await ground_actions.prepare(body,requested,seated,animations.library)
	if not is_instance_valid(body):return null
	if body.shape_values!=requested:
		last_error="Body shape changed during ground action preparation";return null
	last_error=ground_actions.error if result==null else ""
	return result
func finish_frame(model:Node3D,delta:float)->void:
	pending_cloth_delta=delta
	var weapon_pending:bool=twohand.prepare(model.action,model.elapsed,model.action_duration())
	var seat_pending:bool=seat.prepare(model)
	if not weapon_pending and not seat_pending:cloth.advance(delta)
func _after_seat_ik(revision:int)->void:
	if revision==seat_cloth_revision:return
	seat_cloth_revision=revision
	cloth.advance(pending_cloth_delta)
func _after_weapon_ik(revision:int)->void:
	if revision==cloth_ik_revision:return
	cloth_ik_revision=revision
	cloth.advance(pending_cloth_delta)
func supports(clip:StringName)->bool:return animations.library.has_animation(clip)
func report_unsupported(clip:String)->void:
	if reported_unsupported.has(clip):return
	reported_unsupported[clip]=true
	push_warning("Axis action not yet available: "+clip)

func select_clip(action:String,variant:String)->String:
	if not variant.is_empty():return variant
	if action=="attack" and weapon.enabled and supports("attack_sword_a"):
		# Heavy-combo carrier comparison remains a diagnostic: it did not remove
		# the rapid torso motion and has a different multi-hit duration.
		if weapon.item_id=="great_club":return "attack_sword_a"
		var clip:String=["attack_sword_a","attack_sword_b","attack_sword_c"][attack_sequence%3]
		attack_sequence+=1;return clip
	return action
