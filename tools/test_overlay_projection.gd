extends SceneTree
const Overlay = preload("res://scripts/world_editor/city_overlay.gd")
var failed := 0
func _initialize() -> void: run.call_deferred()
func original(overlay: Control, points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector3 in points:
		var local: Vector3=overlay._camera_inverse*point
		if local.z > -overlay._near: return PackedVector2Array()
		result.append(overlay.project_local(local))
	return result
func run() -> void:
	var camera:=Camera3D.new(); root.add_child(camera)
	var overlay:=Overlay.new()
	var rng:=RandomNumberGenerator.new(); rng.seed=67311
	var checked:=0
	for mode in [Camera3D.PROJECTION_ORTHOGONAL,Camera3D.PROJECTION_PERSPECTIVE,Camera3D.PROJECTION_FRUSTUM]:
		camera.projection=mode; camera.size=80; camera.near=.05; camera.far=40000; camera.h_offset=.2; camera.v_offset=.3; camera.frustum_offset=Vector2(.1,-.2)
		for pose in 12:
			camera.position=Vector3(rng.randf_range(-2000,2000),rng.randf_range(2,10000),rng.randf_range(-2000,2000))
			camera.rotation_degrees=Vector3(-90 if pose==0 else rng.randf_range(-89,-5),rng.randf_range(-180,180),0)
			overlay._camera_inverse=camera.get_camera_transform().affine_inverse(); overlay._projection=camera.get_camera_projection(); overlay._near=camera.near; overlay._projection_size=Vector2(1600,1000)
			var points:Array=[]
			for i in 129:
				points.append(camera.get_camera_transform()*Vector3(rng.randf_range(-200,200),rng.randf_range(-100,100),rng.randf_range(-2000,-1)))
			var before:=original(overlay,points); var after:PackedVector2Array=overlay.project(points)
			if before!=after: failed+=1; print("FAIL: exact packed projection mode=",mode," pose=",pose)
			checked+=points.size()
			points[64]=camera.get_camera_transform()*Vector3(0,0,-.01)
			if original(overlay,points)!=overlay.project(points):failed+=1;print("FAIL: near rejection")
	print("OVERLAY_PROJECTION exact_points=",checked," failures=",failed)
	overlay.free(); camera.free(); quit(0 if failed==0 else 1)
