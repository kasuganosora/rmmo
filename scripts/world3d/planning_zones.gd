extends RefCounted
const S=preload("res://scripts/world3d/document_schema.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")

static func schema() -> Dictionary:
	var point:={"type":"array","items":S.number(-100000,100000),"minItems":2,"maxItems":2}
	return {"type":"object","properties":{"id":{"type":"string","maxLength":80},"name":{"type":"string","maxLength":120},"polygon":{"type":"array","items":point,"minItems":3,"maxItems":64},"min_y":S.number(-10000,10000),"max_y":S.number(-10000,10000),"purpose":{"type":"string","enum":["no_build","no_vegetation","reserved_passage"]},"locked":{"type":"boolean"},"hidden":{"type":"boolean"}},"required":["id","polygon","min_y","max_y","purpose"],"additionalProperties":false}

static func polygon(zone: Dictionary) -> PackedVector2Array:
	var out:=PackedVector2Array()
	for p in zone.polygon: out.append(Vector2(p[0],p[1]))
	return out

static func valid(zones: Variant) -> bool:
	if not zones is Array or zones.size()>128: return false
	var ids:={}
	for zone in zones:
		if not S.validate(zone,schema()).is_empty(): return false
		if not str(zone.id).is_valid_identifier() or ids.has(zone.id) or zone.max_y-zone.min_y<.1: return false
		ids[zone.id]=true
		var p:=polygon(zone)
		if Poly.area(Array(p))<1: return false
		for i in p.size():
			if p[i].distance_to(p[(i+1)%p.size()])<.05: return false
			var incoming: Vector2=p[i]-p[posmod(i-1,p.size())]; var outgoing: Vector2=p[(i+1)%p.size()]-p[i]
			if absf(incoming.cross(outgoing))<.00001 and incoming.dot(outgoing)<0: return false
			for j in range(i+1,p.size()):
				if p[i].distance_to(p[j])<.05: return false
				if j==i+1 or (i==0 and j==p.size()-1): continue
				if Geometry2D.segment_intersects_segment(p[i],p[(i+1)%p.size()],p[j],p[(j+1)%p.size()])!=null: return false
				for at in [p[i],p[(i+1)%p.size()]]:
					if Geometry2D.get_closest_point_to_segment(at,p[j],p[(j+1)%p.size()]).distance_to(at)<.00001: return false
		if Geometry2D.triangulate_polygon(p).size()!=(p.size()-2)*3: return false
	return true

static func obstacles(meta: Dictionary, purpose: String="building") -> Array:
	var result: Array=[]
	for zone in meta.get("editor_layout",{}).get("zones",[]):
		if purpose=="building" and zone.purpose=="no_vegetation": continue
		if purpose=="vegetation" and zone.purpose=="no_build": continue
		var p:=polygon(zone); var triangles:=Geometry2D.triangulate_polygon(p)
		for i in range(0,triangles.size(),3):
			var poly:=PackedVector2Array([p[triangles[i]],p[triangles[i+1]],p[triangles[i+2]],p[triangles[i]]])
			var bounds:=AABB(Vector3(poly[0].x,zone.min_y,poly[0].y),Vector3(0,zone.max_y-zone.min_y,0))
			for point in poly: bounds=bounds.expand(Vector3(point.x,zone.min_y,point.y))
			result.append({"polygon":poly,"bounds":bounds,"zone_id":zone.id})
	return result
