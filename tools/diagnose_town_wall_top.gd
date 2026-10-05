extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var raw:=Doc.authoritative_extras("D:/code/rmmo_runtime/cache/world3d/medieval_town_walls/map.gltf")
	var settings: Dictionary=raw.extras.editor_layout.fortifications[0].settings
	var plan:=preload("res://scripts/world3d/fortification_plan.gd").new().build(settings)
	var doc:=Doc.new(); var host:=Node3D.new(); root.add_child(host)
	for i in settings.points.size():
		var a:=Vector3(settings.points[i][0],0,settings.points[i][1]); var b:=Vector3(settings.points[(i+1)%settings.points.size()][0],0,settings.points[(i+1)%settings.points.size()][1]); var p:=a.lerp(b,.5)
		if plan.access_routes.any(func(r):return Vector2(r.room[0]-p.x,r.room[2]-p.z).length()<8): continue
		var ids: Array=[]
		for r in raw.extras.rmmo_records:
			if not r.has("fortification") or r.position[1]+r.size[1]*.5<7: continue
			if Vector2(r.position[0]-p.x,r.position[2]-p.z).length()>Vector2(r.size[0],r.size[2]).length()*.5+1: continue
			var node: MeshInstance3D=doc._mesh(r); var spec:=Stream._spec(node); node.free(); Stream._make_body(host,spec); ids.append(r.uuid)
		for frame in 3: await physics_frame
		var samples: Array=[]
		for t in [0.,-.05,.05]:
			var q: Vector3=p+(b-a).normalized()*t
			var hit:=host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(q+Vector3.UP*8,q+Vector3.UP*7))
			samples.append({"offset":t,"hit":hit.position if not hit.is_empty() else null,"uuid":str(hit.collider.get_meta("uuid")) if not hit.is_empty() else ""})
		print("WALL_TOP ",i," ",JSON.stringify(samples)," candidates=",ids)
		for node in host.get_children(): node.free()
	quit()
