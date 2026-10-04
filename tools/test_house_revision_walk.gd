extends "res://tools/test_world3d_buildings.gd"
## Unpainted isolated geometry: character clearance and closed wall apertures.
func run()->void:
	var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=2.1
	for preset in Blueprint.medieval_presets():
		var plan:=Blueprint.generate(preset.parameters)
		check(plan.ok,"recipe "+preset.id)
		var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.25,0),Vector3(60,.5,60))
		for r in plan.records:
			if r.get("collision","")=="none":continue
			r.building.id="test";doc.records.append(r)
		var host:=Node3D.new();root.add_child(host);var scene:=doc.build();host.add_child(scene)
		Stream.sync(scene,host,Vector3.ZERO);await physics()
		var body:=WalkBody.new();body.floor_snap_length=.2
		var shape:=CollisionShape3D.new();shape.shape=capsule;shape.position.y=.15;body.add_child(shape);host.add_child(body)
		var walk_nav:=WalkNavigation.new();host.add_child(walk_nav)
		var authority:=preload("res://scripts/world3d/world_authority.gd").new()
		if preset.parameters.get("compound")=="courtyard":
			var edge:float=plan.parameters.depth/2+plan.parameters.annex_depth
			plan.stairs.append({"floor":0,"bottom":[0,0,edge+2],"top":[0,plan.parameters.base_height,edge-1]})
		for stair in plan.stairs:
			for reverse in [false,true]:
				var route:Array=stair.get("waypoints",[stair.bottom,stair.top]).duplicate(true)
				if reverse:route.reverse()
				body.position=Blueprint.vec(route[0])+Vector3(0,.905,0);body.velocity=Vector3.ZERO
				for point in route.slice(1):
					authority.mount(body,walk_nav,"revision")
					var target:=Blueprint.vec(point)
					for tick in 400:
						var flat:=Vector3(target.x-body.position.x,0,target.z-body.position.z)
						if flat.length()<.17 and absf(body.position.y-.9-target.y)<.15:break
						await physics_frame;authority.move_intent(tick,flat.normalized(),2.5)
					check(Vector2(body.position.x-target.x,body.position.z-target.z).length()<.3 and absf(body.position.y-.9-target.y)<.2,preset.id+" stair="+str(stair.floor)+" reverse="+str(reverse)+" target="+str(target)+" actual="+str(body.position))
					authority.release()
		print("HOUSE_WALK ",preset.id," failures=",failed)
		host.free();await physics()
	print("HOUSE_REVISION_WALK_FINISHED failures=",failed);quit(1 if failed else 0)
