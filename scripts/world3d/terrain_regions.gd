extends RefCounted
## Editable local-XZ polygons; compact derived coverage, never extra geometry.
const S=preload("res://scripts/world3d/document_schema.gd")
const Zones=preload("res://scripts/world3d/planning_zones.gd")
const RESOLUTION=257

static func polygon_schema() -> Dictionary:
	return Zones.schema().properties.polygon
static func request_schema() -> Dictionary:
	return {"type":"object","properties":{"id":{"type":"string","maxLength":80},"terrain_ids":{"type":"array","items":{"type":"string"},"minItems":1,"maxItems":64},"polygon":polygon_schema(),"material_id":{"type":"string"},"feather":S.number(1,24),"opacity":S.number(.01,1)},"required":["id","terrain_ids","polygon","material_id"]}
static func polygon_valid(points: Array) -> bool:
	return Zones.valid([{"id":"region","polygon":points,"min_y":0,"max_y":1,"purpose":"no_build"}])
static func valid(record: Dictionary) -> bool:
	if not record.has("terrain_regions"): return true
	if not record.has("terrain_mesh") or record.has("surface_paint"): return false
	var data: Variant=record.terrain_regions
	if not data is Dictionary or data.keys().size()!=2 or not data.get("materials") is Array or not data.get("regions") is Array: return false
	if data.materials.is_empty() or data.materials.size()>2 or data.regions.is_empty() or data.regions.size()>32: return false
	var ids:={}; var count:=0
	var schema:={"type":"object","properties":{"id":{"type":"string","maxLength":80},"polygon":polygon_schema(),"feather":S.number(1,24),"opacity":S.number(.01,1),"layer":S.number(0,data.materials.size()-1,true)},"required":["id","polygon","feather","opacity","layer"]}
	for region in data.regions:
		if not S.validate(region,schema).is_empty() or not str(region.id).is_valid_identifier() or ids.has(region.id) or not polygon_valid(region.polygon): return false
		ids[region.id]=true; count+=region.polygon.size()
	return count<=256
static func points(region: Dictionary) -> PackedVector2Array:
	return Zones.polygon(region)
static func bounds(polygon: PackedVector2Array) -> Rect2:
	var r:=Rect2(polygon[0],Vector2.ZERO)
	for p in polygon: r=r.expand(p)
	return r
static func compact(data: Dictionary) -> void:
	var used: Array=[]
	for r in data.regions:
		# JSON reads integral values as floats; array membership is type-sensitive.
		var layer:=int(r.layer)
		if not used.has(layer): used.append(layer)
	used.sort(); var materials: Array=[]
	for index in used: materials.append(data.materials[index])
	for r in data.regions: r.layer=used.find(int(r.layer))
	data.materials=materials
static func work(record: Dictionary) -> int:
	var total:=0; var span:=Vector2(record.size[0],record.size[2])
	for region in record.get("terrain_regions",{}).get("regions",[]):
		var rect:=bounds(points(region)).grow(region.feather).intersection(Rect2(-span*.5,span))
		if not rect.has_area(): continue
		var cells:=rect.size/span*float(RESOLUTION-1)+Vector2(2,2)
		total+=ceili(cells.x)*ceili(cells.y)*region.polygon.size()
	return total
static func mask(record: Dictionary) -> Image:
	var image:=Image.create(RESOLUTION,RESOLUTION,false,Image.FORMAT_RG8)
	var span:=Vector2(record.size[0],record.size[2]); var step:=span/float(RESOLUTION-1)
	for region in record.get("terrain_regions",{}).get("regions",[]):
		var polygon:=points(region); var feather: float=region.feather
		var rect:=bounds(polygon).grow(feather)
		var lo:=Vector2i(((rect.position+span*.5)/step).floor()).clamp(Vector2i.ZERO,Vector2i(RESOLUTION-1,RESOLUTION-1))
		var hi:=Vector2i(((rect.end+span*.5)/step).ceil()).clamp(Vector2i.ZERO,Vector2i(RESOLUTION-1,RESOLUTION-1))
		for z in range(lo.y,hi.y+1):
			for x in range(lo.x,hi.x+1):
				var p:=Vector2(x,z)*step-span*.5; var distance:=INF
				for i in polygon.size(): distance=minf(distance,p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p,polygon[i],polygon[(i+1)%polygon.size()])))
				distance=sqrt(distance)*(1. if Geometry2D.is_point_in_polygon(p,polygon) else -1.)
				var weight:=smoothstep(-feather*.5,feather*.5,distance)*float(region.opacity)
				if weight<=0.: continue
				var c:=image.get_pixel(x,z)*(1.-weight); c[int(region.layer)]+=weight; image.set_pixel(x,z,c)
	# Texels include the exact shared edge. Shader samples texel centres and LOD 0
	# so different sized neighbours do not sample beyond their coverage domain.
	return image
