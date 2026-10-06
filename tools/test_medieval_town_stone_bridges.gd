extends "res://tools/test_world3d_mcp.gd"
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
const Meshes=preload("res://scripts/world3d/bridge_mesh.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Road=preload("res://scripts/world3d/road_plan.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
var CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_stone_bridges/map.gltf"
var OUTPUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_stone_bridges"
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):CANDIDATE=arg.trim_prefix("--map=")
		if arg.begins_with("--out="):OUTPUT=arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	if "--clearance" in OS.get_cmdline_user_args():
		CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_bridge_clearance/map.gltf"; OUTPUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_bridge_clearance"
	create_timer(600).timeout.connect(func():quit(2)); Engine.max_fps=60
	var doc=Doc.open_file(CANDIDATE); check(doc!=null,"load actual converted town")
	if doc==null: quit(1); return
	var bridges: Array=doc.records.filter(func(r):return r.has("bridge_mesh")); check(bridges.size()==5,"five physical stone bridges")
	var ports:=preload("res://scripts/world3d/road_bridges.gd").resolve(doc.map_meta.editor_layout); check(ports.ok and ports.portals.size()==5,"five original road edges retain bridge bindings")
	var overlap:=0.0
	for port in ports.portals:
		for r in doc.records:
			if not r.has("road_mesh"): continue
			for shape in Foot.record_shapes(r):
				var intersection:=Road.intersection(Array(shape.polygon).slice(0,-1),port.polygon)
				if not intersection.is_empty(): overlap+=Poly.area(intersection)
	check(overlap<.02,"no old road polygons remain under the five arches: "+str(overlap))
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(CANDIDATE); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"full saved town runtime loads")
	if loaded[0]==null: quit(1); return
	var host:=Node3D.new(); root.add_child(host); host.add_child(loaded[0])
	var body:=CharacterBody3D.new(); var collision:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.height=2.1; capsule.radius=.3; collision.shape=capsule; body.add_child(collision); host.add_child(body); body.floor_snap_length=.3
	var measurements: Array=[]
	for r in bridges:
		var d: Dictionary=r.bridge_mesh; var transform:=Transform3D(Basis.from_euler(Data.vec(r.rotation)*PI/180),Data.vec(r.position)); var forward:=transform.basis.x; var normal:=transform.basis.z
		Stream.sync(loaded[0],host,transform.origin); for frame in 8: await physics_frame
		var max_error:=0.0; var misses:=0
		for i in ceili(d.length)+5:
			var x: float=-d.length*.5-1.5+(d.length+3)*i/float(ceili(d.length)+4)
			for side in [-1,0,1]:
				var point: Vector3=transform*Vector3(x,Meshes.height_at(x,d),(d.width-1.16)*.35*side)
				var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*3,point+Vector3.DOWN*8); query.exclude=[body.get_rid()]
				var hit:=host.get_world_3d().direct_space_state.intersect_ray(query)
				if hit.is_empty(): misses+=1
				else: max_error=maxf(max_error,absf(hit.position.y-point.y))
		check(misses==0 and max_error<.025,"full width bridge and approach surface continuity: "+r.editor_name+" error="+str(max_error))
		for direction in [1,-1]:
			body.position=transform*Vector3((-d.length*.5-1)*direction,1.08,0); body.velocity=Vector3.ZERO; var grounded:=true
			for frame in 1500:
				await physics_frame; body.velocity=forward*10*direction+Vector3.DOWN*2; body.move_and_slide()
				if frame>8: grounded=grounded and body.is_on_floor()
				if (transform.affine_inverse()*body.position).x*direction>d.length*.5+.8: break
			check(grounded and (transform.affine_inverse()*body.position).x*direction>d.length*.5+.8,"2.1m player crosses both bridgeheads: "+r.editor_name+" direction="+str(direction))
		var opening: float=(d.length-2-(d.arches-1)*d.recipe.pier_width)/d.arches; var index:=floori(d.arches/2.0); var x: float=-d.length*.5+1+index*(opening+d.recipe.pier_width)+opening*.5
		var center: Vector3=transform*Vector3(x,-1,0); var query:=PhysicsRayQueryParameters3D.create(center-normal*d.width,center+normal*d.width); query.exclude=[body.get_rid()]
		check(host.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"river arch opening remains unobstructed: "+r.editor_name)
		var navigation:=preload("res://scripts/world_editor/bridge_clearance.gd").fit(r.duplicate(true),doc.records,false)
		check(navigation.ok and navigation.get("applicable",false),"2.5m actual water-to-intrados clearance: "+r.editor_name+" "+JSON.stringify(navigation))
		if navigation.ok and navigation.applicable:
			var boat:=BoxShape3D.new(); boat.size=Vector3(2,2.5,1)
			var passage:=PhysicsShapeQueryParameters3D.new(); passage.shape=boat
			var start: Vector3=transform*Vector3(navigation.center_x,0,-d.width*.5-2); start.y=navigation.water_level+1.25
			passage.transform=Transform3D(transform.basis,start); passage.margin=.001; passage.motion=normal*(d.width+4); passage.exclude=[body.get_rid()]
			var space:=host.get_world_3d().direct_space_state
			check(space.intersect_shape(passage).is_empty() and space.cast_motion(passage)[0]>.9999,"2m wide / 2.5m high boat envelope crosses complete bridge: "+r.editor_name)
		measurements.append({"id":r.uuid,"surface_error":max_error,"ray_misses":misses,"navigation":navigation})
	host.free()
	var report:={"failures":failed,"candidate_sha256":FileAccess.get_sha256(CANDIDATE),"old_road_overlap_area":overlap,"bridges":measurements}
	var file:=FileAccess.open(OUTPUT.path_join("runtime_result.json"),FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("TOWN_STONE_RUNTIME_FINISHED failures=",failed); quit(1 if failed else 0)
