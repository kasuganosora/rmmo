extends RefCounted
## Deterministic frontage packing along a user-authored, level street centerline.
const Blueprint = preload("res://scripts/world3d/building_blueprint.gd")
const Schema = preload("res://scripts/world3d/document_schema.gd")
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
const Footprint = preload("res://scripts/world_editor/building_footprint.gd")

static func schema() -> Dictionary:
	return {"type":"object","properties":{
		"parameters":Blueprint.schema(),"points":{"type":"array","items":Schema.vector(-100000,100000),"minItems":2,"maxItems":32},
		"road_width":Schema.number(2,30),"setback":Schema.number(.2,10),"gap":Schema.number(.2,20),
		"side":{"type":"string","enum":["left","right","both"]},"width_variation":Schema.number(0,.3),
		"max_buildings":Schema.number(1,16,true)},"required":["points"],"additionalProperties":false}

static func plan(args: Dictionary) -> Dictionary:
	var error := Schema.validate(args,schema())
	if not error.is_empty(): return Blueprint.fail(error)
	var settings := {"road_width":6.0,"setback":.6,"gap":1.0,"side":"both","width_variation":.12,"max_buildings":16}; settings.merge(args,true)
	var points: Array[Vector3]=[]
	for value in args.points: points.append(Blueprint.vec(value))
	for i in points.size()-1:
		if points[i].distance_to(points[i+1])<1: return Blueprint.fail("相邻道路点至少间隔 1 米")
		if absf(points[i+1].y-points[0].y)>.005: return Blueprint.fail("沿街建筑目前需要同一标高的平地道路")
		if i>0 and (points[i]-points[i-1]).normalized().dot((points[i+1]-points[i]).normalized())<-.995: return Blueprint.fail("道路不能沿原路折返")
		for j in range(i+2,points.size()-1):
			if crossed(Vector2(points[i].x,points[i].z),Vector2(points[i+1].x,points[i+1].z),Vector2(points[j].x,points[j].z),Vector2(points[j+1].x,points[j+1].z)): return Blueprint.fail("道路中心线不能自相交")
	var parameters: Dictionary = Blueprint.medieval_presets()[0].parameters.duplicate(true); parameters.merge(args.get("parameters",{}),true)
	var initial := Blueprint.generate(parameters)
	if not initial.ok: return initial
	var rng := RandomNumberGenerator.new(); rng.seed=int(parameters.seed)
	var placements: Array=[]; var occupied: Array=[]; var skipped := 0; var limited := false
	var side_counts := {-1:0,1:0}
	var sides: Array = [-1,1] if settings.side=="both" else ([-1] if settings.side=="left" else [1])
	for i in points.size()-1:
		var tangent := (points[i+1]-points[i]).normalized(); var length := points[i].distance_to(points[i+1])
		for side in sides:
			var cursor: float = settings.road_width/2+settings.setback
			var attempts := 0
			while cursor<length-settings.road_width/2 and attempts<512:
				if placements.size()>=int(settings.max_buildings): limited=true; break
				if sides.size()==2 and side==-1 and side_counts[-1]>=ceili(float(settings.max_buildings)/2): break
				attempts+=1
				var p: Dictionary = parameters.duplicate(true)
				p.width=snappedf(clampf(parameters.width*(1+rng.randf_range(-settings.width_variation,settings.width_variation)),5.5 if p.layout!="standard" else 9.0,24),.05)
				if p.compound=="courtyard": p.width=maxf(p.width,2*p.annex_width+2.5)
				p.seed=int(parameters.seed)+placements.size()
				var building := Blueprint.generate(p)
				if not building.ok: return building
				var bounds := Geometry.bounds(building.records)
				if cursor+bounds.size.x>length-settings.road_width/2-settings.setback: break
				var normal := Vector3(-tangent.z,0,tangent.x)*float(side)
				var yaw := rad_to_deg(atan2(normal.x,normal.z)); var basis := Basis(Vector3.UP,deg_to_rad(yaw))
				var at: Vector3 = points[i]+tangent*(cursor+bounds.size.x/2-side*bounds.get_center().x)+normal*(settings.road_width/2+settings.setback-bounds.position.z)
				var footprint := Footprint.components(building.records,at,basis)
				cursor+=bounds.size.x+settings.gap
				if Footprint.batches_overlap(footprint,occupied) or intersects_road(footprint,points,settings.road_width/2): skipped+=1; continue
				occupied.append_array(footprint)
				placements.append({"position":Blueprint.arr(at),"yaw":yaw,"parameters":p})
				side_counts[side]+=1
			if attempts==512: return Blueprint.fail("道路太长或折角过密，请分段生成")
	if placements.is_empty(): return Blueprint.fail("道路段没有足够空间容纳建筑和转角净空")
	return {"ok":true,"request":{"placements":placements},"street":{"points":args.points,"road_width":settings.road_width,"setback":settings.setback,"side":settings.side,"skipped_corners":skipped,"limit_reached":limited,"building_count":placements.size()}}

static func intersects_road(shapes: Array, points: Array[Vector3], radius: float) -> bool:
	for shape in shapes:
		var polygon: PackedVector2Array = shape.polygon
		for i in points.size()-1:
			var a := Vector2(points[i].x,points[i].z); var b := Vector2(points[i+1].x,points[i+1].z)
			if Geometry2D.is_point_in_polygon(a,polygon) or Geometry2D.is_point_in_polygon(b,polygon): return true
			for k in polygon.size()-1:
				var c: Vector2=polygon[k]; var d: Vector2=polygon[k+1]
				if Geometry2D.segment_intersects_segment(a,b,c,d)!=null: return true
				if c.distance_to(Geometry2D.get_closest_point_to_segment(c,a,b))<radius or d.distance_to(Geometry2D.get_closest_point_to_segment(d,a,b))<radius or a.distance_to(Geometry2D.get_closest_point_to_segment(a,c,d))<radius or b.distance_to(Geometry2D.get_closest_point_to_segment(b,c,d))<radius: return true
	return false

static func crossed(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	if Geometry2D.segment_intersects_segment(a,b,c,d)!=null: return true
	var direction := (b-a).normalized()
	if absf((c-a).cross(direction))>.001 or absf((d-a).cross(direction))>.001: return false
	return maxf(minf((c-a).dot(direction),(d-a).dot(direction)),0)<=minf(maxf((c-a).dot(direction),(d-a).dot(direction)),a.distance_to(b))+.001
