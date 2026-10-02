extends RefCounted
## A seeded, bounded planner. Existing records remain obstacles even when hidden or locked.
const Blueprint = preload("res://scripts/world3d/building_blueprint.gd")
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
const Footprint = preload("res://scripts/world_editor/building_footprint.gd")
const Schema = preload("res://scripts/world3d/document_schema.gd")
const EDGE := .3

static func schema() -> Dictionary:
	return {"type":"object","properties":{
		"from":Schema.vector(-100000,100000),"to":Schema.vector(-100000,100000),
		"style":{"type":"string","enum":["urban_village","medieval","standard"]},
		"mode":{"type":"string","enum":["single","block"]},"density":{"type":"string","enum":["low","medium","high"]},
		"yaw":{"type":"number","enum":[0,90,180,-90]},"seed":Schema.number(0,2147483647,true),
		"max_buildings":Schema.number(1,16,true),"plan_token":{"type":"string","minLength":64,"maxLength":64}},
		"required":["from","to"],"additionalProperties":false}

static func plan(args: Dictionary, records: Array, reservations: Array = []) -> Dictionary:
	var issue := Schema.validate(args,schema())
	if not issue.is_empty(): return Blueprint.fail(issue)
	var settings := {"style":"urban_village","mode":"single","density":"medium","yaw":0,"seed":1,"max_buildings":8}; settings.merge(args,true)
	var a := Blueprint.vec(args.from); var b := Blueprint.vec(args.to)
	if absf(a.y-b.y)>.005: return Blueprint.fail("区域生成需要同一标高的平地区域")
	var low := Vector3(minf(a.x,b.x),a.y,minf(a.z,b.z)); var high := Vector3(maxf(a.x,b.x),a.y,maxf(a.z,b.z))
	var width := high.x-low.x; var depth := high.z-low.z
	if minf(width,depth)<1 or maxf(width,depth)>500: return Blueprint.fail("区域边长须在 1～500 米之间；过小区域仍可能放不下建筑")
	var basis := Basis(Vector3.UP,deg_to_rad(settings.yaw)); var center := (low+high)/2
	var rotated: bool=absf(float(settings.yaw))==90
	var extent := Vector2(depth,width) if rotated else Vector2(width,depth)
	extent-=Vector2.ONE*EDGE*2
	var rng := RandomNumberGenerator.new(); rng.seed=int(settings.seed)
	var gap: float={"low":4.0,"medium":2.5,"high":1.4}[settings.density]
	var ideal := Vector2(11,15) if settings.style=="urban_village" else (Vector2(8,14) if settings.style=="medieval" else Vector2(14,17))
	var minimum := Vector2(9.6,12.1) if settings.style=="urban_village" else (Vector2(6.2,11.1) if settings.style=="medieval" else Vector2(9.1,13.1))
	var columns := 1; var rows := 1
	if settings.mode=="block":
		var variation := rng.randf_range(.85,1.15)
		columns=clampi(roundi(extent.x/(ideal.x*variation+gap)),1,mini(8,maxi(1,floori((extent.x+gap)/(minimum.x+gap)))))
		rows=clampi(roundi(extent.y/(ideal.y*variation+gap)),1,mini(8,maxi(1,floori((extent.y+gap)/(minimum.y+gap)))))
	var cell := Vector2((extent.x-(columns-1)*gap)/columns,(extent.y-(rows-1)*gap)/rows)
	var obstacles: Array=reservations.duplicate()
	for record in records:
		for shape in Footprint.record_shapes(record):
			if Footprint.supporting_ground(record,shape.bounds.end.y,a.y): continue
			if shape.bounds.end.x<low.x or shape.bounds.position.x>high.x or shape.bounds.end.z<low.z or shape.bounds.position.z>high.z: continue
			obstacles.append(shape)
	var slots: Array=[]
	for z in rows:
		for x in columns: slots.append(Vector2i(x,z))
	# Seeded traversal spreads capped batches across the region instead of filling one corner.
	for i in range(slots.size()-1,0,-1):
		var j := rng.randi_range(0,i); var swap: Vector2i=slots[i]; slots[i]=slots[j]; slots[j]=swap
	var placements: Array=[]; var occupied: Array=[]; var skipped := 0; var collision_attempts := 0
	var limit: int=1 if settings.mode=="single" else settings.max_buildings
	for slot in slots:
		if placements.size()>=limit: break
		var accepted := false
		var slot_center := -extent/2+cell/2+Vector2(slot)*(cell+Vector2.ONE*gap)
		for attempt in 12:
			var p := variant(settings.style,cell,rng,attempt==11)
			var building := Blueprint.generate(p)
			if not building.ok or building.records.size()>Blueprint.MAX_PARTS: continue
			var bounds := Footprint.local_bounds(building.records)
			# Keep the entrance approach inside the lot as well as every visible overhang.
			bounds=bounds.expand(Blueprint.vec(building.entrance))
			if bounds.size.x>cell.x+.001 or bounds.size.z>cell.y+.001: continue
			var slack := Vector2(cell.x-bounds.size.x,cell.y-bounds.size.z)
			var jitter := Vector2.ZERO if attempt==0 else Vector2(rng.randf_range(-.5,.5)*slack.x,rng.randf_range(-.5,.5)*slack.y)
			var local := Vector3(slot_center.x+jitter.x-bounds.get_center().x,0,slot_center.y+jitter.y-bounds.get_center().z)
			var at := center+basis*local
			var footprint := Footprint.components(building.records,at,basis)
			# Protect a small access margin against props, not only other generated houses.
			var reservation := bounds; reservation.position.x-=.1; reservation.position.z-=.1; reservation.size.x+=.2; reservation.size.z+=.2
			var corners: Array[Vector3]=[]
			for i in 8: corners.append(at+basis*reservation.get_endpoint(i))
			var reserved := [Footprint.from_points(corners)]
			if Footprint.batches_overlap(reserved,obstacles) or Footprint.batches_overlap(reserved,occupied): collision_attempts+=1; continue
			placements.append({"parameters":building.parameters,"position":Blueprint.arr(at),"yaw":float(settings.yaw)})
			occupied.append_array(footprint); accepted=true; break
		if not accepted: skipped+=1
	if placements.is_empty(): return {"ok":false,"error":"区域内没有足够的无碰撞空间，请扩大或移动区域，也可换一个方案","skipped_slots":skipped,"collision_attempts":collision_attempts}
	var request := {"placements":placements}
	return {"ok":true,"request":request,"plan_token":JSON.stringify(request).sha256_text(),"region":{
		"from":Blueprint.arr(low),"to":Blueprint.arr(high),"style":settings.style,"mode":settings.mode,"density":settings.density,"yaw":settings.yaw,"seed":settings.seed,
		"building_count":placements.size(),"skipped_slots":skipped,"collision_attempts":collision_attempts,"limit_reached":placements.size()>=limit and slots.size()>placements.size()}}

static func variant(style: String, cell: Vector2, rng: RandomNumberGenerator, minimum: bool) -> Dictionary:
	var p: Dictionary=Blueprint.layout_defaults("urban_village") if style=="urban_village" else (Blueprint.medieval_presets()[0].parameters.duplicate(true) if style=="medieval" else Blueprint.defaults())
	p.seed=rng.randi_range(0,2147483647)
	p.template="shop" if rng.randf()<.25 else "house"
	p.floors=1 if minimum else rng.randi_range(2,5 if style=="urban_village" else 3)
	p.floor_height=4.0
	var extra_x := .1; var extra_z := 1.1
	if style=="urban_village":
		p.balcony="none" if minimum else ["none","front","corner"][rng.randi_range(0,2)]
		p.balcony_depth=rng.randf_range(1.4,1.8)
		p.facade_color=["white","cream","rose","green"][rng.randi_range(0,3)]
		p.roof_canopy=not minimum and rng.randf()<.7; p.roof_tank=not minimum and rng.randf()<.8; p.ground_canopy=not minimum and rng.randf()<.7
		if p.balcony!="none": extra_z=p.balcony_depth+.1
		if p.balcony=="corner": extra_x+=p.balcony_depth
	elif style=="medieval":
		p.jetty=0 if minimum else rng.randf_range(0,.5); p.eaves=.25
		p.roof_axis="width" if rng.randf()<.5 else "depth"; p.roof_pitch=rng.randf_range(35,50)
		p.shutters=not minimum and rng.randf()<.8; p.style="timber" if rng.randf()<.35 else "plaster"
		p.dormers=0 if minimum or rng.randf()<.45 else 1
		extra_x=.65; extra_z=1.4+p.jetty
	else:
		p.roof="flat" if rng.randf()<.3 else "gable"; p.style="plaster" if rng.randf()<.5 else "timber"
	var min_width := 9.5 if style=="urban_village" else (5.5 if style=="medieval" else 9.0)
	var min_depth := 12.0 if style=="standard" else (11.0 if style=="urban_village" else 10.0)
	var maximum := Vector2(minf(24,cell.x-extra_x),minf(30,cell.y-extra_z))
	p.width=min_width if minimum else snappedf(rng.randf_range(min_width,maxf(min_width,maximum.x)),.05)
	p.depth=min_depth if minimum else snappedf(rng.randf_range(min_depth,maxf(min_depth,maximum.y)),.05)
	if style=="urban_village": p.bedrooms=rng.randi_range(1,clampi(floori((p.depth-5.6)/2.8),1,3))
	else: p.rooms_per_floor=1 if minimum or p.depth<14 else rng.randi_range(1,2)
	return p
