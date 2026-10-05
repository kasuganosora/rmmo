extends "res://tools/test_world3d_fortification_access.gd"
var CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_walls/map.gltf"
var OUTPUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_walls"
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):CANDIDATE=arg.trim_prefix("--map=")
		if arg.begins_with("--out="):OUTPUT=arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	create_timer(900).timeout.connect(func():quit(2)); Engine.max_fps=60
	var raw:=Doc.authoritative_extras(CANDIDATE); check(raw.has("extras"),"read saved candidate recipe; runtime loader validates document below")
	if not raw.has("extras"): quit(1); return
	var settings: Dictionary=raw.extras.editor_layout.fortifications[0].settings
	var plan:=preload("res://scripts/world3d/fortification_plan.gd").new().build(settings)
	check(plan.ok and plan.access_routes.size()==settings.tower_indices.size() and plan.access_routes.size()>20,"native recipe regenerates every selected accessible tower")
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(CANDIDATE); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"full town wall runtime loads")
	if loaded[0]==null: quit(1); return
	var host:=Node3D.new(); root.add_child(host); host.add_child(loaded[0]); var scene: Node3D=loaded[0]; var space:=host.get_world_3d().direct_space_state
	for i in plan.access_routes.size():
		var route: Dictionary=plan.access_routes[i]; var room:=Data.vec(route.room); Stream.sync(scene,host,room); await physics()
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(room+Vector3.UP,room-Vector3.UP))
		check(not hit.is_empty() and absf(hit.position.y-.03)<.01,"tower %d stone floor above graded ground"%i)
		check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Data.vec(route.entry)+Vector3.UP*3.5,room+Vector3.UP*3.5)).is_empty(),"tower %d city-side entrance remains clear"%i)
	var capsule:=CapsuleShape3D.new(); capsule.radius=.3; capsule.height=2.1
	for gate in settings.gates:
		var a:=Vector2(settings.points[int(gate.segment)][0],settings.points[int(gate.segment)][1]); var b:=Vector2(settings.points[(int(gate.segment)+1)%settings.points.size()][0],settings.points[(int(gate.segment)+1)%settings.points.size()][1]); var p:=a.lerp(b,gate.t); var n:=Vector3(-(b-a).y,0,(b-a).x).normalized(); var center:=Vector3(p.x,0,p.y)
		Stream.sync(scene,host,center); await physics()
		var q:=PhysicsShapeQueryParameters3D.new(); q.margin=.002; q.shape=capsule
		var y:=1.09
		if gate.get("kind","land")=="water":
			var box:=BoxShape3D.new(); box.size=Vector3(2,2.5,2); q.shape=box; y=-.2
		q.transform=Transform3D(Basis.IDENTITY,center-n*7+Vector3.UP*y); q.motion=n*14
		var fractions:=space.cast_motion(q); check(fractions[0]>.999,"unobstructed physical crossing "+gate.id)
	var wall_misses:=0; var point_seams:=0
	for i in settings.points.size():
		var a:=Vector3(settings.points[i][0],0,settings.points[i][1]); var b:=Vector3(settings.points[(i+1)%settings.points.size()][0],0,settings.points[(i+1)%settings.points.size()][1]); var p:=a.lerp(b,.5)
		if plan.access_routes.any(func(r):return Vector2(r.room[0]-p.x,r.room[2]-p.z).length()<8): continue
		Stream.sync(scene,host,p); await physics(); var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*8,p+Vector3.UP*7))
		if hit.is_empty(): point_seams+=1
		# A zero-width ray exactly on two float32 triangle edges can miss both.
		# Verify actual player support with the same 2.1 m capsule as gate tests.
		var q:=PhysicsShapeQueryParameters3D.new(); q.shape=capsule; q.margin=.002; q.transform=Transform3D(Basis.IDENTITY,p+Vector3.UP*9.05); q.motion=Vector3.DOWN
		var travel:=space.cast_motion(q)
		if absf((8.-travel[0])-7.5)>.02: wall_misses+=1; print("WALL_SUPPORT_MISS ",i," fraction=",travel)
	check(wall_misses==0,"every traced wall segment physically supports the player capsule")
	var file:=FileAccess.open(OUTPUT.path_join("runtime_result.json"),FileAccess.WRITE); file.store_string(JSON.stringify({"failures":failed,"candidate_sha256":FileAccess.get_sha256(CANDIDATE),"towers":plan.access_routes.size(),"gates":settings.gates.size(),"wall_top_misses":wall_misses,"point_ray_seams":point_seams},"\t")); file.close()
	host.free(); print("TOWN_WALL_RUNTIME_FINISHED failures=",failed); quit(1 if failed else 0)
