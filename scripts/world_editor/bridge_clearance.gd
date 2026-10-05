extends RefCounted
## Actual Blender mesh intrados, not the road surface, controls navigable clearance.
const Data=preload("res://scripts/world3d/city_layout.gd")
const D=preload("res://scripts/world3d/bridge_data.gd")
const Meshes=preload("res://scripts/world3d/bridge_mesh.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const HEIGHT=2.5
const WIDTH=2.0
const MARGIN=.05
static var profiles: Dictionary={}
static var measurements: Dictionary={}
static func clip_x(poly: Array,bound: float,keep_right: bool) -> Array:
	var out: Array=[]
	for i in poly.size():
		var a: Vector3=poly[i]; var b: Vector3=poly[(i+1)%poly.size()]
		var ai: bool=a.x>=bound if keep_right else a.x<=bound
		var bi: bool=b.x>=bound if keep_right else b.x<=bound
		if ai: out.append(a)
		if ai!=bi: out.append(a.lerp(b,(bound-a.x)/(b.x-a.x)))
	return out
static func continuous_roof(mesh: Mesh,center: float) -> float:
	# Clip every triangle to the complete passage strip. This catches a tooth or
	# low stone between ray samples and includes trim outside the deck width.
	var faces:=mesh.get_faces(); var low:=INF; var left:=center-WIDTH*.5; var right:=center+WIDTH*.5
	for i in range(0,faces.size(),3):
		var a: Vector3=faces[i]; var b: Vector3=faces[i+1]; var c: Vector3=faces[i+2]
		if minf(a.x,minf(b.x,c.x))>right or maxf(a.x,maxf(b.x,c.x))<left: continue
		var poly:=clip_x(clip_x([a,b,c],left,true),right,false)
		for p in poly: low=minf(low,p.y)
	return low
static func profile(record: Dictionary,shifted:=false) -> Array:
	var flat:=record.duplicate(true); flat.bridge_mesh.camber=0.0
	var d: Dictionary=flat.bridge_mesh; var key:=Data.token([d,record.asset_path,shifted])
	if profiles.has(key): return profiles[key]
	var mesh:=Meshes.new().build(flat)
	if mesh==null: return []
	var bvh:=TriangleMesh.new()
	if not bvh.create_from_faces(mesh.get_faces()): return []
	var openings: Array=[]; var span: float=(d.length-2-(d.arches-1)*d.recipe.pier_width)/d.arches
	for i in int(d.arches):
		var center: float=-d.length*.5+1+i*(span+d.recipe.pier_width)+span*.5
		var offsets: Array=[0.0]
		if shifted:
			for offset in [.5,1.,1.5,2.,2.5,3.]:
				if offset+WIDTH*.5<span*.5-.05: offsets.append(offset); offsets.append(-offset)
		for offset in offsets:
			var samples: Array=[]; var axis: float=center+offset
			for xi in 9:
				var x: float=axis-WIDTH*.5+WIDTH*xi/8.0
				for z in [-d.width*.5-.05,-d.width*.5+.03,-d.width*.25,0,d.width*.25,d.width*.5-.03,d.width*.5+.05]:
					var hit:=bvh.intersect_ray(Vector3(x,-d.depth-1,z),Vector3.UP)
					if hit.is_empty(): continue # Open air outside a bevel is not an obstruction.
					var y: float=hit.position.y
					var factor: float=pow(sin(PI*(x/d.length+.5)),2)*clampf((y+d.depth)/(d.depth-.25),0,1)
					samples.append({"x":x,"z":z,"y":y,"factor":factor})
			openings.append({"arch_index":i,"center_x":axis,"samples":samples})
	if profiles.size()>=8: profiles.erase(profiles.keys()[0])
	profiles[key]=openings
	return openings
static func water_surfaces(records: Array,record: Dictionary) -> Array:
	var surfaces: Array=[]; var bounds: AABB=Foot.record_shape(record).bounds
	var rect:=Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z)
	for r in records:
		if r.get("surface_id")!="water": continue
		var rb: AABB=Foot.record_shape(r).bounds
		if not rect.intersects(Rect2(rb.position.x,rb.position.z,rb.size.x,rb.size.z),true): continue
		var t:=Transform3D(Basis.from_euler(Data.vec(r.rotation)*PI/180),Data.vec(r.position)); var polys: Array=[]
		if r.has("channel_mesh"): polys=preload("res://scripts/world3d/channel_surface.gd").local_polygons(r)
		else:
			var s:=Data.vec(r.size)*.5; polys=[[Vector3(-s.x,s.y,-s.z),Vector3(s.x,s.y,-s.z),Vector3(s.x,s.y,s.z),Vector3(-s.x,s.y,s.z)]]
		for poly in polys:
			var p: Array=Array(poly).map(func(v):return t*v)
			surfaces.append({"polygon":PackedVector2Array(p.map(func(v):return Vector2(v.x,v.z))),"plane":Plane(p[0],p[1],p[2])})
	return surfaces
static func water_at(surfaces: Array,p: Vector3) -> float:
	var height:=-INF
	for surface in surfaces:
		if not Geometry2D.is_point_in_polygon(Vector2(p.x,p.z),surface.polygon): continue
		var hit: Variant=surface.plane.intersects_ray(Vector3(p.x,100000,p.z),Vector3.DOWN)
		if hit!=null: height=maxf(height,hit.y)
	return height
static func fit(record: Dictionary,records: Array,automatic:=true) -> Dictionary:
	var waters:=water_surfaces(records,record)
	if waters.is_empty(): return {"ok":true,"applicable":false}
	var openings:=profile(record)
	if openings.is_empty(): return Data.fail("无法读取石桥实际拱洞几何")
	var t:=Transform3D(Basis.from_euler(Data.vec(record.rotation)*PI/180),Data.vec(record.position))
	var best: Dictionary={}; var required:=INF
	for attempt in 2:
		for opening in openings:
			var need:=0.0; var levels: Array=[]; var valid: bool=not opening.samples.is_empty()
			for sample in opening.samples:
				var p: Vector3=t*Vector3(sample.x,0,sample.z); var water:=water_at(waters,p)
				if not is_finite(water): valid=false; break
				levels.append(water)
				if sample.factor<.00001: valid=false; break
				need=maxf(need,(water+HEIGHT+MARGIN-t.origin.y-sample.y)/sample.factor)
			if valid and need<required: required=need; best=opening.duplicate(true); best.levels=levels
		if not best.is_empty(): break
		openings=profile(record,true)
	if best.is_empty(): return Data.fail("水面上找不到连续 2 米宽的主通航孔，请调整桥位、孔数或跨度")
	var d: Dictionary=record.bridge_mesh; var requested: float=d.camber; var maximum:=minf(5,d.length*.15/PI)
	if automatic:
		var fitted:=maxf(requested,ceilf(required*1000)/1000)
		if fitted>maximum+.000001: return Data.fail("主通航孔须有 2.5 米净高 / 2 米净宽；所需拱高 %.2f 米超过坡度上限，请加长桥梁/引道或提高两岸标高"%fitted)
		d.camber=fitted
	var clearance:=INF; var water_max:=-INF
	for i in best.samples.size():
		var sample: Dictionary=best.samples[i]; var level: float=best.levels[i]
		clearance=minf(clearance,t.origin.y+sample.y+sample.factor*d.camber-level); water_max=maxf(water_max,level)
	if clearance<HEIGHT: return Data.fail("主通航孔净高 %.2f 米，不足硬性下限 2.5 米；启用自动抬拱或增加拱高"%clearance)
	# Recheck the deformed triangles: interpolated vertices differ slightly from
	# the analytic rise used for fitting. Cache only geometry, never water levels.
	var key:=Data.token([d,record.asset_path,best.center_x])
	var roof: float=measurements.get(key,INF)
	if not is_finite(roof):
		var actual:=Meshes.new().build(record)
		if actual==null: return Data.fail("无法验证生成后的石桥净空")
		roof=continuous_roof(actual,best.center_x)
		if not is_finite(roof): return Data.fail("生成后的拱洞测量点缺失")
		if measurements.size()>=8: measurements.erase(measurements.keys()[0])
		measurements[key]=roof
	clearance=t.origin.y+roof-water_max
	if clearance<HEIGHT: return Data.fail("实际石拱网格净高 %.2f 米不足 2.5 米，请增加拱高"%clearance)
	record.bounds_size=Data.xyz(D.dimensions(d))
	return {"ok":true,"applicable":true,"arch_index":best.arch_index,"center_x":best.center_x,"width":WIDTH,"clearance":clearance,"water_level":water_max,"required_height":HEIGHT,"adjusted":d.camber>requested+.000001}
