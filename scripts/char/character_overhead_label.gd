extends Label3D
## One model-aware anchor for names and cast text; no fixed actor height.
var model:Node3D
var clearance:=.16

func _ready()->void:
	billboard=BaseMaterial3D.BILLBOARD_ENABLED
	vertical_alignment=VERTICAL_ALIGNMENT_BOTTOM
	process_priority=50

func _process(_delta:float)->void:
	if not is_visible_in_tree():return
	update_anchor()

func update_anchor()->void:
	if not is_instance_valid(model) or model.skeleton==null or not model.bones.has("head"):return
	var skeleton:Skeleton3D=model.skeleton
	var index:int=model.bones.head
	var pose:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(index)
	var camera:=get_viewport().get_camera_3d()
	var up:=camera.global_basis.y.normalized() if camera!=null else Vector3.UP
	var top:=pose.origin.dot(up)
	for category in ["Body","Hair","HeadAccessory"]:
		for mesh in model.gear.get(category,[]):
			if not mesh is MeshInstance3D or mesh.mesh==null or not mesh.is_visible_in_tree():continue
			var box:AABB=mesh.mesh.get_aabb()
			var transform:Transform3D=mesh.global_transform
			if mesh.skin!=null:
				for binding in mesh.skin.get_bind_count():
					if mesh.skin.get_bind_name(binding)==skeleton.get_bone_name(index) or (mesh.skin.get_bind_name(binding).is_empty() and mesh.skin.get_bind_bone(binding)==index):
						transform=pose*mesh.skin.get_bind_pose(binding)
						break
			# The combined Body bounds include extended arms. Only its crown
			# contributes; face, hair and headwear use their full bounds.
			var combined:bool=mesh.name=="Body"
			for corner in (1 if combined else 8):
				var point:Vector3=transform*box.get_endpoint(corner)
				if combined:
					var world_box:AABB=transform*box
					point=Vector3(pose.origin.x,world_box.end.y,pose.origin.z)
				top=maxf(top,point.dot(up))
	global_position=pose.origin+up*(top-pose.origin.dot(up)+clearance*model.global_basis.get_scale().abs().y)
