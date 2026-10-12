extends RefCounted
## Clip existing UV-painted road patches without repainting unrelated town streets.
const Data=preload("res://scripts/world3d/city_layout.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
static func geometry(r: Dictionary) -> Dictionary:
	var node:=MeshInstance3D.new(); node.mesh=Surface.mesh(r,null); var g:=Paint.geometry(node); node.free(); return g
static func cut(r: Dictionary,mask: Array,y: float,deck_line:Array=[]) -> Dictionary:
	var transform:=Transform3D(Basis.from_euler(Data.vec(r.rotation)*PI/180),Data.vec(r.position))
	var inverse:=transform.affine_inverse(); var local_mask: Array=[]
	for v in mask:
		var p: Vector3=inverse*Vector3(v.x,y,v.y); local_mask.append(Vector2(p.x/r.size[0],p.z/r.size[2]))
	var polys: Array=[]; var area:=0.0; var lost:=0.0;var removed_polygons:Array=[]
	for raw in r.road_mesh.polygons:
		var p: Array=raw.map(func(v):return Vector2(v[0],v[1]))
		var intersection:=preload("res://scripts/world3d/road_plan.gd").intersection(p,local_mask)
		var aligned:=true
		if not deck_line.is_empty():
			for point:Vector2 in intersection:
				var grade:Array=r.road_mesh.get("grade",[0,0]);var local_y:float=r.size[1]*.5+point.x*r.size[0]*grade[0]+point.y*r.size[2]*grade[1]
				if r.road_mesh.has("elevations"):local_y=elevation(r,point)
				var world:Vector3=transform*Vector3(point.x*r.size[0],local_y,point.y*r.size[2])
				var delta:Vector3=deck_line[1]-deck_line[0];var t:float=Vector2(world.x-deck_line[0].x,world.z-deck_line[0].z).dot(Vector2(delta.x,delta.z))/Vector2(delta.x,delta.z).length_squared()
				if not is_finite(local_y) or absf(world.y-lerpf(deck_line[0].y,deck_line[1].y,t))>.08:aligned=false;break
		var fragments:Array=Poly.subtract(p,local_mask) if aligned else [p]
		if aligned and not intersection.is_empty():removed_polygons.append(intersection)
		var previous:=Poly.area(p); var remaining:=0.0
		for f in fragments: remaining+=Poly.area(f)
		lost+=previous-remaining; area+=previous
		polys.append_array(fragments)
	if lost*r.size[0]*r.size[2]<.00001: return {"ok":true,"changed":false}
	if r.get("editor_locked",false) or r.get("editor_hidden",false) or r.has("event_template") or r.has("event"): return Data.fail("旧桥面有保护或事件："+r.uuid)
	if absf(r.rotation[0])+absf(r.rotation[2])>.001:return Data.fail("旧桥面不能绕 X/Z 整体倾斜："+r.uuid)
	for p in r.get("surface_paint",[]):
		if p.surface!=0 or p.mapping!="uv": return Data.fail("仅能保留按 UV 刷制的路面，侧面或手动投影需先处理："+r.uuid)
	if lost>=area-.00000001: return {"ok":true,"changed":true,"removed":true}
	var copy:=r.duplicate(true); var normalized: Array=[]
	for f in polys:
		var clean:=preload("res://scripts/world3d/road_plan.gd").normalized_patch(f.map(func(p):return p*32.0),Vector3.ZERO)
		if not clean.is_empty(): normalized.append(clean)
	if r.road_mesh.has("elevations"):
		var heights:Array=[]
		for poly:Array in normalized:
			var row:Array=[]
			for point:Array in poly:
				var height:=elevation(r,Vector2(point[0],point[1]))
				if not is_finite(height):return Data.fail("裁切路面高程无法插值")
				row.append(height)
			heights.append(row)
		copy.road_mesh.elevations=heights
	copy.road_mesh.polygons=normalized
	if copy.has("terrain_follow"):copy.terrain_follow.polygons=normalized.duplicate(true)
	for field:Dictionary in [copy.road_mesh,copy.get("terrain_follow",{})]:
		if not field.has("kerbs"):continue
		var trimmed:=clip_kerbs(field.kerbs,removed_polygons,Data.vec(r.size))
		if trimmed.is_empty():field.erase("kerbs")
		else:field.kerbs=trimmed
	if normalized.is_empty(): return {"ok":true,"changed":true,"removed":true}
	if not Surface.valid(copy): return Data.fail("旧路面裁切无效："+r.uuid)
	if not r.get("surface_paint",[]).is_empty():
		var before:=geometry(r); var after:=geometry(copy)
		if not before.ok or not after.ok: return Data.fail("旧路面刷面几何无法解析")
		var old: Dictionary=before.surfaces[0]; var fresh: Dictionary=after.surfaces[0]; var entries: Array=[]
		for face in fresh.faces:
			var triangle: int=fresh.faces[face].triangles[0]; var center:=Vector3.ZERO
			for k in 3: center+=fresh.arrays[Mesh.ARRAY_VERTEX][fresh.indices[triangle*3+k]]/3.0
			var old_face:=-1
			for oface in old.faces:
				for tri in old.faces[oface].triangles:
					var points:=PackedVector2Array()
					for k in 3:
						var v: Vector3=old.arrays[Mesh.ARRAY_VERTEX][old.indices[tri*3+k]]; points.append(Vector2(v.x,v.z))
					if Geometry2D.is_point_in_polygon(Vector2(center.x,center.z),points): old_face=int(oface); break
				if old_face>=0: break
			if old_face<0: return Data.fail("无法保留旧路面逐面材质："+r.uuid)
			for entry in r.surface_paint:
				if entry.face!=old_face: continue
				var paint: Dictionary=entry.duplicate(true); paint.face=face; paint.geometry=fresh.signature; entries.append(paint); break
		copy.surface_paint=entries
	if not Paint.valid(copy): return Data.fail("裁切后材质记录无效")
	return {"ok":true,"changed":true,"removed":false,"record":copy}

static func clip_kerbs(parts:Array,masks:Array,size_:Vector3)->Array:
	var output:Array=[]
	for part:Dictionary in parts:
		# Section vertex 0 is the exposed pavement boundary, shared with the
		# road polygons. Preserve profile, UV distance and untouched end caps.
		var a:=Vector2(part.a[0][0]/size_.x,part.a[0][2]/size_.z)
		var b:=Vector2(part.b[0][0]/size_.x,part.b[0][2]/size_.z)
		var intervals:Array=[Vector2(0,1)]
		for mask:Array in masks:
			var lo:=0.;var hi:=1.
			for i in mask.size():
				var edge:Vector2=mask[(i+1)%mask.size()]-mask[i];var normal:=Vector2(-edge.y,edge.x)
				var da:float=normal.dot(a-mask[i]);var db:float=normal.dot(b-mask[i]);var slope:=db-da
				if absf(slope)<1e-12:
					if da<-.0000001:hi=-1.;break
				elif slope>0:lo=maxf(lo,-da/slope)
				else:hi=minf(hi,-da/slope)
			if hi<=lo+.0000001:continue
			var remaining:Array=[]
			for span:Vector2 in intervals:
				if hi<=span.x or lo>=span.y:remaining.append(span);continue
				if lo>span.x:remaining.append(Vector2(span.x,lo))
				if hi<span.y:remaining.append(Vector2(hi,span.y))
			intervals=remaining
		for span:Vector2 in intervals:
			if (span.y-span.x)*part.length<.00001:continue
			var next:=part.duplicate(true)
			for endpoint:String in ["a","b"]:
				var t:float=span.x if endpoint=="a" else span.y
				for i in 6:next[endpoint][i]=Data.xyz(Data.vec(part.a[i]).lerp(Data.vec(part.b[i]),t))
			next.u=part.u+span.x*part.length;next.length=part.length*(span.y-span.x)
			next.cap_a=part.cap_a or span.x>0.;next.cap_b=part.cap_b or span.y<1.
			output.append(next)
	return output

static func elevation(r:Dictionary,p:Vector2)->float:
	for i in r.road_mesh.polygons.size():
		var poly:Array=r.road_mesh.polygons[i];var indices:=Geometry2D.triangulate_polygon(PackedVector2Array(poly.map(func(v):return Vector2(v[0],v[1]))))
		for j in range(0,indices.size(),3):
			var a:=Vector2(poly[indices[j]][0],poly[indices[j]][1]);var b:=Vector2(poly[indices[j+1]][0],poly[indices[j+1]][1]);var c:=Vector2(poly[indices[j+2]][0],poly[indices[j+2]][1])
			var den:float=(b-a).cross(c-a)
			if absf(den)<.00000001:continue
			var u:float=(p-a).cross(c-a)/den;var v:float=(b-a).cross(p-a)/den
			if u>=-.0001 and v>=-.0001 and u+v<=1.0001:
				var h:Array=r.road_mesh.elevations[i];return h[indices[j]]*(1.-u-v)+h[indices[j+1]]*u+h[indices[j+2]]*v
	return NAN
