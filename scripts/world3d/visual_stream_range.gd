extends RefCounted
## Request all objects the game camera can see, independent of object category.
## A rotation-independent envelope avoids request churn while orbiting in place.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const CAMERA_ORBIT_MARGIN_M:=32.0 # Current camera arm <=12m plus its height/offset.

static func projection_radius(projection:Projection)->int:
	# Projection.get_far_plane_half_extents assumes a symmetric frustum in 4.8.
	# Invert all clip corners instead, including off-axis and orthogonal views.
	if projection.determinant()==0.0:return -1
	var inverse:=projection.inverse()
	var length_squared:=0.0
	for z:float in [-1.0,1.0]:
		for y:float in [-1.0,1.0]:
			for x:float in [-1.0,1.0]:
				var point:Vector4=inverse*Vector4(x,y,z,1.0)
				if point.w==0.0 or not point.is_finite():return -1
				var squared:=Vector3(point.x,point.y,point.z).length_squared()/(point.w*point.w)
				if not is_finite(squared):return -1
				length_squared=maxf(length_squared,squared)
	return maxi(1,int(ceil((sqrt(length_squared)+CAMERA_ORBIT_MARGIN_M)/Stream.CHUNK_M)))

static func sync(map_root:Node,camera:Camera3D,origin:Vector3)->bool:
	if not is_instance_valid(map_root) or not is_instance_valid(camera):return false
	var queue:Node=map_root.get_node_or_null("DeferredAssets")
	if queue!=null:queue.set_view_direction(-camera.global_basis.z)
	var projection:=camera.get_camera_projection()
	if map_root.has_meta("stream_visual_projection") and map_root.get_meta("stream_visual_projection")==projection:return false
	var radius:=projection_radius(projection)
	# An invalid camera must not silently replace the last valid extent by a
	# near-only fallback. Real camera projections have finite clipping planes.
	if radius<0:return false
	map_root.set_meta("stream_visual_projection",projection)
	var changed:bool=Stream.set_render_radius(map_root,radius)
	if queue!=null:
		queue.visual_render_radius=radius
		queue.prioritize(origin)
	return changed
