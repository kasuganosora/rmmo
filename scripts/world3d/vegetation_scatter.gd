extends RefCounted
## Persistent recipes and deterministic, area-weighted sampling of simple polygons.
const S=preload("res://scripts/world3d/document_schema.gd")
const Zones=preload("res://scripts/world3d/planning_zones.gd")

static func object(properties: Dictionary, required: Array=[]) -> Dictionary:
	return {"type":"object","properties":properties,"required":required,"additionalProperties":false}
static func array(items: Dictionary, maximum: int, minimum: int=0) -> Dictionary:
	return {"type":"array","items":items,"minItems":minimum,"maxItems":maximum}
static func text(maximum: int) -> Dictionary: return {"type":"string","maxLength":maximum}
static func defaults() -> Dictionary:
	return {"name":"区域植被","height":0.0,"seed":1,"count":32,"spacing":4.0,"scale_min":.85,"scale_max":1.15,"boundary_margin":.5,"collision":true}
static func settings_schema() -> Dictionary:
	var fields:={"id":text(80),"name":text(120),"polygon":Zones.schema().properties.polygon,"asset_ids":array(text(2048),8,1),"height":S.number(-10000,10000),"seed":S.number(0,2147483647,true),"count":S.number(1,256,true),"spacing":S.number(.5,100),"scale_min":S.number(.1,5),"scale_max":S.number(.1,5),"boundary_margin":S.number(0,20),"collision":{"type":"boolean"}}
	return object(fields,["id","polygon","asset_ids"])
static func request_schema() -> Dictionary:
	var result:=settings_schema(); result.properties.plan_token=text(64); return result
static func manifest_schema() -> Dictionary:
	var settings:=settings_schema(); settings.required=settings.properties.keys()
	return array(object({"version":S.number(1,1,true),"settings":settings,"parts":array(object({"id":text(100),"signature":text(64)},["id","signature"]),256)},["version","settings","parts"]),128)
static func valid_settings(settings: Dictionary) -> bool:
	if not S.validate(settings,settings_schema()).is_empty(): return false
	if not str(settings.id).is_valid_identifier() or settings.id.is_empty(): return false
	if settings.scale_min>settings.scale_max: return false
	var seen:={}
	for id in settings.asset_ids:
		if id.is_empty() or seen.has(id): return false
		seen[id]=true
	if not Zones.valid([{"id":"scatter","polygon":settings.polygon,"min_y":0,"max_y":1,"purpose":"no_vegetation"}]): return false
	var box:=Rect2(Vector2(settings.polygon[0][0],settings.polygon[0][1]),Vector2.ZERO)
	for p in settings.polygon: box=box.expand(Vector2(p[0],p[1]))
	return box.size.x<=1000 and box.size.y<=1000 and box.get_area()<=250000
static func valid(regions: Variant) -> bool:
	if not S.validate(regions,manifest_schema()).is_empty(): return false
	var ids:={}; var parts:={}
	for region in regions:
		if not valid_settings(region.settings) or ids.has(region.settings.id): return false
		ids[region.settings.id]=true
		for part in region.parts:
			if not part.id.is_valid_identifier() or part.id.is_empty() or parts.has(part.id) or part.signature.length()!=64: return false
			parts[part.id]=true
	return true
static func polygon(raw: Array) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for p in raw: result.append(Vector2(p[0],p[1]))
	return result
static func area(poly: PackedVector2Array) -> float:
	var sum_:=0.0
	for i in range(1,poly.size()-1): sum_+=(poly[i]-poly[0]).cross(poly[i+1]-poly[0])
	return absf(sum_)*.5
static func inside(poly: PackedVector2Array, regions: Array) -> bool:
	var remaining: Array=[poly]
	for region in regions:
		var next: Array=[]
		for fragment in remaining: next.append_array(Geometry2D.clip_polygons(fragment,region))
		remaining=next
		if remaining.is_empty(): return true
	var outside:=0.0
	for fragment in remaining: outside+=area(fragment)
	return outside<.0001
static func candidates(settings: Dictionary) -> Array:
	var p:=polygon(settings.polygon); var triangles:=Geometry2D.triangulate_polygon(p)
	var weights: Array=[]; var total:=0.0
	for i in range(0,triangles.size(),3):
		total+=absf((p[triangles[i+1]]-p[triangles[i]]).cross(p[triangles[i+2]]-p[triangles[i]]))*.5
		weights.append(total)
	var rng:=RandomNumberGenerator.new(); rng.seed=int(settings.seed)
	var result: Array=[]
	for index in mini(8192,int(settings.count)*64):
		var at:=rng.randf()*total; var tri:=0
		while tri<weights.size()-1 and at>weights[tri]: tri+=1
		var u:=sqrt(rng.randf()); var v:=rng.randf()
		var point:=p[triangles[tri*3]]*(1-u)+p[triangles[tri*3+1]]*(u*(1-v))+p[triangles[tri*3+2]]*(u*v)
		result.append({"slot":index,"point":point,"asset":rng.randi_range(0,settings.asset_ids.size()-1),"yaw":rng.randf_range(-180,180),"scale":rng.randf_range(settings.scale_min,settings.scale_max)})
	return result
