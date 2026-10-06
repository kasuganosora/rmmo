extends SceneTree
## Read-only diagnostic: production collision geometry and movement, with navigation
## deliberately bypassed to distinguish physical stair traversal from path finding.
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
class Walker extends CharacterBody3D:
	var surface_id:="ground"
	func _sense_surface():pass
class NavigationStub extends Node:
	var ready_for_queries:=true
	func near_surface(_point,_flat,_vertical):return true
var report:Dictionary={"scope":"generated geometry physical traversal; navigation, saved maps, camera comfort and VR are not certified", "capsule_height_m":2.1,"cases":[],"body_samples":[]}
var failures:=0
var sequence:=0

func _initialize()->void:call_deferred("run")

func run()->void:
	# The background runner supplies a wall-clock timeout; accelerated physics
	# intentionally advances more than 300 simulation seconds across the matrix.
	var cases:Array=Blueprint.medieval_presets()+Blueprint.urban_presets()
	for template:String in ["house","shop","inn"]:
		cases.append({"id":"standard_"+template,"parameters":Blueprint.defaults().merged({"template":template,"floors":3},true)})
	cases.append({"id":"narrow_4m_rotated","parameters":Blueprint.medieval_presets()[0].parameters.merged({"width":5.5,"depth":14.0,"floor_height":4.0,"floors":3},true),"yaw":37.0})
	cases.append({"id":"standard_4m_rotated","parameters":Blueprint.defaults().merged({"floor_height":4.0,"floors":3},true),"yaw":90.0})
	cases.append({"id":"urban_4m_rotated","parameters":Blueprint.urban_presets()[0].parameters.merged({"width":9.5,"depth":11.0,"floor_height":4.0,"floors":2,"bedrooms":1,"balcony":"none","roof_canopy":false,"roof_tank":false},true),"yaw":-23.0})
	for offset in [-.2,.2]:
		var variant:Dictionary=cases.back().duplicate(true)
		variant.id="urban_offset_"+str(offset);variant.walk_offset=offset;cases.append(variant)
	cases.append({"id":"urban_six_floor_turns","parameters":Blueprint.layout_defaults("urban_village").merged({"width":11,"depth":15,"floors":6,"bedrooms":3,"balcony":"corner"},true),"yaw":37.0})
	for sample:Dictionary in cases:await inspect_building(sample)
	inspect_body()
	var camera=preload("res://scripts/world3d/third_person_camera.gd").new()
	var focus_height:=clampf(camera.actor_height*.84,1.4,1.7)
	report.camera={"focus_above_feet_m":focus_height,"unobstructed_height_above_feet_m":focus_height+sin(camera.pitch)*camera.distance,"distance_m":camera.distance,"pitch_deg":rad_to_deg(camera.pitch)}
	camera.free()
	report.failures=failures
	var output:=Art.review_path("building_metrics/audit.json")
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("building metrics audit: failures=%d report=%s"%[failures,output])
	quit(0 if failures==0 else 1)

func inspect_building(sample:Dictionary)->void:
	var plan:=Blueprint.generate(sample.parameters)
	if not plan.ok:
		failures+=1;report.cases.append({"id":sample.id,"error":plan.error});print("FAIL generation ",sample.id," ",plan.error);return
	var host:=Node3D.new();root.add_child(host)
	var frame:=Transform3D(Basis(Vector3.UP,deg_to_rad(sample.get("yaw",0.0))),Vector3(15.07,0,12.11))
	var doc:=Doc.new()
	for record:Dictionary in plan.records:
		var mesh:=doc._mesh(record)
		mesh.transform=frame*mesh.transform
		Stream._make_body(host,Stream._spec(mesh));mesh.free()
	var body:=Walker.new();body.floor_snap_length=.2
	var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.height=2.1;capsule.radius=.3;shape.shape=capsule;shape.position.y=.15;body.add_child(shape);host.add_child(body)
	var nav:=NavigationStub.new();host.add_child(nav)
	var authority:=preload("res://scripts/world3d/world_authority.gd").new()
	await physics_frame;await physics_frame
	var result:Dictionary={"id":sample.id,"parameters":plan.parameters,"yaw":sample.get("yaw",0.0),"slab_clear_height_m":float(plan.parameters.floor_height)-Blueprint.SLAB,"traversals":[]}
	var floor_ids:Array=[]
	for stair:Dictionary in plan.stairs:
		if not floor_ids.has(stair.floor):floor_ids.append(stair.floor)
	for floor_id in floor_ids:
		var stairs:Array=plan.stairs.filter(func(s):return s.floor==floor_id)
		var targets:Array=[]
		for stair:Dictionary in stairs:
			var offset:=Vector3(float(sample.get("walk_offset",0)),0,0)
			targets.append(frame*(Blueprint.vec(stair.bottom)+offset));targets.append(frame*(Blueprint.vec(stair.top)+offset))
		body.position=targets[0]+Vector3(0,.905,0);body.velocity=Vector3.ZERO
		authority.mount(body,nav,"metric_audit");sequence=0
		for direction:String in ["up","down"]:
			var route:Array=targets.duplicate()
			if direction=="down":route.reverse()
			var ok:=true;var max_vertical_step:=0.0
			for destination:Vector3 in route.slice(1):
				for tick:int in 600:
					var delta:=destination-body.position;delta.y=0
					if delta.length()<.10:break
					await physics_frame;sequence+=1
					var previous_y:=body.position.y
					authority.move_intent(sequence,delta.normalized(),2.5)
					max_vertical_step=maxf(max_vertical_step,absf(body.position.y-previous_y))
				for tick:int in 8:
					await physics_frame;sequence+=1;authority.move_intent(sequence,Vector3.ZERO,0)
				var flat:=Vector2(body.position.x-destination.x,body.position.z-destination.z).length()
				if flat>.2 or absf(body.position.y-.9-destination.y)>.15:ok=false;break
			result.traversals.append({"floor":floor_id,"direction":direction,"ok":ok,"max_vertical_step_m":max_vertical_step,"feet_end":Blueprint.arr(body.position-Vector3.UP*.9)})
			if not ok:failures+=1;print("FAIL ",sample.id," floor=",floor_id," direction=",direction," position=",body.position)
			# A failed ascent must not masquerade as a valid descent.
			if not ok:break
		authority.release()
	print("AUDITED ",sample.id," traversals=",result.traversals.size())
	report.cases.append(result);host.free();await physics_frame

func inspect_body()->void:
	# Evaluate the actual approved control vertices and identity morphs; these are
	# body-only standing rest dimensions, excluding hair, shoes and animation.
	var file:=Art.path("characters/base/female_base_v2/female_display_topology.json")
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(file))
	var base:=PackedVector3Array()
	for point:Array in source.points:base.append(Blueprint.vec(point))
	var shapes=preload("res://scripts/char/character_body_shapes.gd")
	for height:float in [-1.0,0.0,1.0]:
		var points:PackedVector3Array=shapes.evaluate(base,{"height":height})
		var low:=INF;var high:=-INF
		for point:Vector3 in points:low=minf(low,point.y);high=maxf(high,point.y)
		report.body_samples.append({"model":"female_base_v2","height_parameter":height,"rest_body_height_m":high-low})
	print("BODY ",report.body_samples)
