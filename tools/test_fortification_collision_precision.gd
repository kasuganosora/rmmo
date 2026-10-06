extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Batch=preload("res://scripts/world3d/fortification_collision_batcher.gd")
var failed:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: failed+=1; push_error(message)
	else: print("PASS: ",message)
func run() -> void:
	create_timer(120).timeout.connect(func():quit(2))
	# These real fan centers previously fell through solely after cell rebasing.
	var ids=["wall_53234bfb77f0d0eb_access_tower_4_ground_floor_18","wall_53234bfb77f0d0eb_access_tower_19_ground_floor_18"]
	var raw:=Doc.authoritative_extras("D:/code/rmmo_runtime/cache/world3d/medieval_town_walls/map.gltf")
	var doc:=Doc.new(); var host:=Node3D.new(); root.add_child(host)
	var entries: Array=[]; var points: Array=[]
	for record in raw.extras.rmmo_records:
		if not record.uuid in ids: continue
		var visual: MeshInstance3D=doc._mesh(record); host.add_child(visual)
		points.append(visual.global_position)
		entries.append(Batch.entry(visual.mesh,visual.global_transform,record.uuid,visual.get_meta("extras")))
	check(entries.size()==2,"both far-origin fan regressions found")
	var batch:=Batch.new(); host.add_child(batch); batch.sync(entries)
	await physics_frame; await physics_frame
	for i in points.size():
		var p: Vector3=points[i]; var space:=host.get_world_3d().direct_space_state
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP,p-Vector3.UP))
		check(not hit.is_empty() and absf(hit.position.y-.03)<.001 and Batch.hit_uuid(hit)==entries[i].uuid,"exact tower fan center keeps stone floor and UUID")
		var capsule:=CapsuleShape3D.new(); capsule.radius=.3; capsule.height=2.1
		var q:=PhysicsShapeQueryParameters3D.new(); q.shape=capsule; q.transform.origin=Vector3(p.x,2,p.z); q.motion=Vector3.DOWN*2
		check(space.cast_motion(q)[0]<.5,"player capsule supported at fan center")
	print("COLLISION_PRECISION_FINISHED failures=",failed); quit(1 if failed else 0)
