extends "res://tools/test_adaptive_terrain_roads.gd"
## A long curb must follow dips/crests between its original endpoints, including
## skewed roads and rotated terrain. Also exercise the existing UI/HTTP contract.
func profile_error(records:Array,ground:Dictionary,height:float)->float:
	var worst:=0.;var pose:=Terrain.transform(ground);var inverse:=pose.affine_inverse()
	for record:Dictionary in records:
		for kerb:Dictionary in record.road_mesh.get("kerbs",[]):
			for rail:int in [2,3]:
				var a:Vector3=City.vec(record.position)+City.vec(kerb.a[rail])
				var b:Vector3=City.vec(record.position)+City.vec(kerb.b[rail])
				for t:float in [.125,.25,.5,.75,.875]:
					var point:=a.lerp(b,t);var local:=inverse*Vector3(point.x,0.,point.z)
					var y:=Terrain.sample(ground,local)
					if not is_finite(y):return INF
					worst=maxf(worst,absf(point.y-(pose*Vector3(local.x,y,local.z)).y-.025-height))
	return worst

func logical()->void:
	super.logical()
	for angle:float in [0.,27.]:
		var ground:=terrain();ground.rotation[1]=angle
		for z in 65:
			for x in 65:ground.terrain_mesh.heights[z*65+x]=.46*cos(x*.5*PI/16.)+.05*sin(z*.5*PI/16.)
		var route:=graph();route.nodes[0].position=[7.,0.,12.];route.nodes[1].position=[25.,0.,20.]
		route.edges[0].width_start=3.;route.edges[0].width_end=3.
		var settings:=Plan.defaults().merged({"follow_terrain":true,"kerb_enabled":true,"kerb_height":.035,"kerb_width":.24},true)
		var plan:=Plan.build(route,settings);var before:Array=plan.records.duplicate(true)
		var fitted:=Adaptive.fit(plan.records,[ground]);check(fitted.ok,"curved-ground kerb fixture prepares at yaw %.0f"%angle)
		if not fitted.ok:continue
		var error:=profile_error(fitted.records,ground,.035)
		check(error<.0002,"full-length kerb rails follow actual terrain triangles at yaw %.0f (error %.6fm)"%[angle,error])
		check(plan.records==before,"curb subdivision does not mutate authored source")
		var refitted:Array=[]
		for record:Dictionary in fitted.records:
			var next:=Fit.fit(record,[ground]);check(next.ok,"saved source can refit")
			if next.ok:refitted.append(next.record)
		check(equivalent(refitted,fitted.records),"repeated terrain-follow refit retains caps, UV and deterministic subdivision")

func check(ok:bool,label:String)->void:
	super.check(ok,label)
	if is_instance_valid(editor) and (label=="native save/reopen preserves adaptive cells and terrain-follow source" or label=="sculpted adaptive road children and ownership survive save/reopen"):
		var roads:Array=editor._doc.records.filter(func(r):return r.has("road_mesh"))
		var ground:Dictionary=editor._doc._find("fine_ground")
		var error:=profile_error(roads,ground,.035)
		super.check(error<.0002,"HTTP-generated and reopened kerb interiors conform (error %.6fm)"%error)
