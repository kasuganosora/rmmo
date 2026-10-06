extends "res://tools/verify_medieval_town_base.gd"
var CURVE_MAP="D:/code/rmmo_runtime/cache/world3d/medieval_town_curves/map.gltf"
var CURVE_RESULT="D:/code/rmmo_runtime/review_artifacts/medieval_town_curves"

func run() -> void:
	create_timer(600).timeout.connect(func():quit(2)); Engine.max_fps=60
	log_file=FileAccess.open(CURVE_RESULT.path_join("runtime_progress.log"),FileAccess.WRITE)
	var candidate_hash:=FileAccess.get_sha256(CURVE_MAP)
	spec=JSON.parse_string(FileAccess.get_file_as_string("res://tools/medieval_town_layout.json"))
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(CURVE_MAP)
	var loaded: Array=await loader.finished
	check(loaded[0]!=null,"load revised town through native runtime loader")
	if loaded[0]!=null:
		await curved_walk(loaded[0])
		if "--curves-only" not in OS.get_cmdline_user_args(): await verify_runtime(loaded[0])
		else: loaded[0].free()
	var f:=FileAccess.open(CURVE_RESULT.path_join("runtime_result.json"),FileAccess.WRITE)
	check(candidate_hash==FileAccess.get_sha256(CURVE_MAP),"candidate stayed unchanged throughout runtime verification")
	f.store_string(JSON.stringify({"failures":failed,"scope":"curves_only" if "--curves-only" in OS.get_cmdline_user_args() else "full","candidate_sha256":candidate_hash},"\t")); f.close()
	print("TOWN_CURVES_RUNTIME failures=",failed); quit(1 if failed else 0)

func curved_walk(scene: Node3D) -> void:
	var doc=Doc.open_file(CURVE_MAP); var graph: Dictionary=doc.map_meta.editor_layout.roads; var audit:=City.analyze(graph)
	var host:=Node3D.new(); root.add_child(host); host.add_child(scene)
	var body:=CharacterBody3D.new(); var shape:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new()
	capsule.height=2.1; capsule.radius=.3; shape.shape=capsule; body.add_child(shape); host.add_child(body); body.floor_snap_length=.3
	for name_ in ["西南外环","东岸长街"]:
		var edges: Array=graph.edges.filter(func(e):return e.name==name_).slice(1,3)
		var points: Array=[]
		for edge in edges: points.append_array(audit.paths[edge.id])
		Stream.sync(scene,host,points[0]); await physics()
		var space:=host.get_world_3d().direct_space_state; var missing:=0; var misses: Array=[]; var boundary_roundoff:=0
		for edge in edges:
			var samples: Array=audit.paths[edge.id]
			for i in samples.size():
				var p: Vector3=samples[i]; var tangent: Vector3=(samples[mini(i+1,samples.size()-1)]-samples[maxi(0,i-1)]).normalized()
				var side:=Vector3(-tangent.z,0,tangent.x)*float(edge.width_start)*.45
				Stream.sync(scene,host,p); await physics()
				for offset in [Vector3.ZERO,side,-side]:
					var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(p+offset+Vector3.UP*4,p+offset-Vector3.UP*2))
					if hit.is_empty() or absf(hit.position.y-.025)>.01:
						# A zero-width ray exactly on a shared triangle vertex may
						# hit the terrain below after float32 glTF conversion. Require
						# all four 1 mm diagonal neighbors to hit pavement; walking
						# across that same boundary is checked independently below.
						var neighbors_ok:=true
						for dx in [-.001,.001]:
							for dz in [-.001,.001]:
								var q: Vector3=p+offset+Vector3(dx,0,dz)
								var near_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(q+Vector3.UP*4,q-Vector3.UP*2))
								neighbors_ok=neighbors_ok and not near_hit.is_empty() and absf(near_hit.get("position",Vector3.INF).y-.025)<.01
						if neighbors_ok: boundary_roundoff+=1; continue
						missing+=1
						if misses.size()<8: misses.append({"position":City.xyz(p+offset),"height":hit.get("position",Vector3.INF).y,"collider":str(hit.get("collider","missing"))})
		check(missing==0,"curved center/edges and 32m seams have pavement collision (1mm boundary tolerance): "+name_+" boundary_roundoff="+str(boundary_roundoff)+" misses="+str(missing)+" "+JSON.stringify(misses))
		Stream.sync(scene,host,points[0]); await physics(); body.position=points[0]+Vector3.UP*1.12
		for i in 12: await physics_frame; body.velocity=Vector3(0,-4,0); body.move_and_slide()
		var index:=1; var max_drop:=0.0
		for frame in 3600:
			await physics_frame
			var delta: Vector3=points[index]-Vector3(body.position.x,0,body.position.z)
			if delta.length()<.3:
				index+=1
				if index>=points.size(): break
				delta=points[index]-Vector3(body.position.x,0,body.position.z)
			Stream.sync(scene,host,body.position); body.velocity=delta.normalized()*12+Vector3(0,-4,0); body.move_and_slide()
			max_drop=maxf(max_drop,1.075-body.position.y)
		check(index>=points.size() and max_drop<.1,"2.1m capsule follows curve across junction and chunk seams: "+name_)
	host.remove_child(scene); host.free()
