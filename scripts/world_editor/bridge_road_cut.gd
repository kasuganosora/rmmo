extends RefCounted
## Clip existing UV-painted road patches without repainting unrelated town streets.
const Data=preload("res://scripts/world3d/city_layout.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
static func geometry(r: Dictionary) -> Dictionary:
	var node:=MeshInstance3D.new(); node.mesh=Surface.mesh(r,null); var g:=Paint.geometry(node); node.free(); return g
static func cut(r: Dictionary,mask: Array,y: float) -> Dictionary:
	var transform:=Transform3D(Basis.from_euler(Data.vec(r.rotation)*PI/180),Data.vec(r.position))
	var inverse:=transform.affine_inverse(); var local_mask: Array=[]
	for v in mask:
		var p: Vector3=inverse*Vector3(v.x,y,v.y); local_mask.append(Vector2(p.x/r.size[0],p.z/r.size[2]))
	var polys: Array=[]; var area:=0.0; var lost:=0.0
	for raw in r.road_mesh.polygons:
		var p: Array=raw.map(func(v):return Vector2(v[0],v[1])); var fragments:=Poly.subtract(p,local_mask)
		var previous:=Poly.area(p); var remaining:=0.0
		for f in fragments: remaining+=Poly.area(f)
		lost+=previous-remaining; area+=previous
		polys.append_array(fragments)
	if lost*r.size[0]*r.size[2]<.00001: return {"ok":true,"changed":false}
	if r.get("editor_locked",false) or r.get("editor_hidden",false) or r.has("event_template") or r.has("event"): return Data.fail("旧桥面有保护或事件："+r.uuid)
	if absf(r.rotation[0])+absf(r.rotation[2])>.001 or r.road_mesh.has("grade"): return Data.fail("旧桥面须为水平路面："+r.uuid)
	for p in r.get("surface_paint",[]):
		if p.surface!=0 or p.mapping!="uv": return Data.fail("仅能保留按 UV 刷制的路面，侧面或手动投影需先处理："+r.uuid)
	if lost>=area-.00000001: return {"ok":true,"changed":true,"removed":true}
	var copy:=r.duplicate(true); var normalized: Array=[]
	for f in polys:
		var clean:=preload("res://scripts/world3d/road_plan.gd").normalized_patch(f.map(func(p):return p*32.0),Vector3.ZERO)
		if not clean.is_empty(): normalized.append(clean)
	copy.road_mesh.polygons=normalized
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
