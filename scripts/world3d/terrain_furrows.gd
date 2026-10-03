extends RefCounted
## Raised cultivation strips clipped to both the field and each original triangle.
## The original ground is the trough; all new faces stay on/above its plane.
const Regions=preload("res://scripts/world3d/terrain_regions.gd")
const MAX_TRIANGLES=48000
const MAX_CLIPS=60000
static var _cache: Dictionary={}
static func maximum_height(record: Dictionary) -> float:
	var result:=0.
	for region in record.get("terrain_regions",{}).get("regions",[]):
		result=maxf(result,region.get("furrows",{}).get("height",0.))
	return result
static func schemas() -> Dictionary:
	var properties: Dictionary=Regions.furrow_schema().properties.duplicate(true); properties.erase("phase")
	properties.merge({"id":{"type":"string","maxLength":80},"terrain_ids":{"type":"array","items":{"type":"string"},"minItems":1,"maxItems":64},"enabled":{"type":"boolean"}})
	return {"type":"object","properties":properties,"required":["id","terrain_ids"],"additionalProperties":false}
static func point(r: Dictionary,x: int,z: int) -> Vector3:
	var t: Dictionary=r.terrain_mesh
	return Vector3((float(x)/t.columns-.5)*r.size[0],t.heights[z*(int(t.columns)+1)+x]*r.size[1],(float(z)/t.rows-.5)*r.size[2])
static func generate(record: Dictionary) -> Dictionary:
	if maximum_height(record)==0.: return {"ok":true,"vertices":PackedVector3Array(),"triangles":0,"clips":0}
	# Native file validation can run on the loader worker. Do not share a mutable
	# cache with live editor operations on the main thread.
	if not Thread.is_main_thread(): return _generate(record)
	# Derived CPU geometry is reused by validation, mesh creation and native save.
	# Include only geometry inputs; changing grass never rebuilds cultivation.
	var regions: Array=[]
	for r in record.get("terrain_regions",{}).get("regions",[]):
		if r.has("furrows"): regions.append([r.polygon,r.furrows])
	var key:=JSON.stringify([record.size,record.terrain_mesh,regions]).sha256_text()
	if _cache.has(key): return _cache[key]
	var result:=_generate(record)
	if _cache.size()>=32: _cache.erase(_cache.keys()[0])
	_cache[key]=result
	return result
static func _generate(record: Dictionary) -> Dictionary:
	var vertices:=PackedVector3Array(); var clips:=0
	var t: Dictionary=record.terrain_mesh; var step:=Vector2(record.size[0]/t.columns,record.size[2]/t.rows)
	for region in record.get("terrain_regions",{}).get("regions",[]):
		if not region.has("furrows"): continue
		var f: Dictionary=region.furrows
		var polygons:=Geometry2D.offset_polygon(Regions.points(region),-float(f.get("setback",0.)))
		for polygon in polygons:
			var axis:=Vector2(cos(deg_to_rad(f.angle)),sin(deg_to_rad(f.angle))); var along:=Vector2(-axis.y,axis.x)
			var box:=Regions.bounds(polygon); var span:=Vector2(record.size[0],record.size[2])
			var lo:=Vector2i(((box.position+span*.5)/step).floor()).clamp(Vector2i.ZERO,Vector2i(t.columns-1,t.rows-1))
			var hi:=Vector2i(((box.end+span*.5)/step).ceil()).clamp(Vector2i.ZERO,Vector2i(t.columns-1,t.rows-1))
			for z in range(lo.y,hi.y+1):
				for x in range(lo.x,hi.x+1):
					if t.holes[z*int(t.columns)+x]: continue
					var corners:=[point(record,x,z),point(record,x+1,z),point(record,x+1,z+1),point(record,x,z+1)]
					for order in [[0,1,2],[0,2,3]]:
						var a: Vector3=corners[order[0]]; var b: Vector3=corners[order[1]]; var c: Vector3=corners[order[2]]
						var plane:=Plane(a,c,b)
						var triangle:=PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])
						var cut:=Geometry2D.intersect_polygons(triangle,polygon); clips+=1
						if clips>MAX_CLIPS: return {"ok":false,"error":"垄沟计算量超出单块预算，请扩大垄距或缩小农田"}
						for piece in cut:
							if absf(plane.normal.y)<cos(deg_to_rad(20.)): return {"ok":false,"error":"农田坡度超过 20 度，请先整平或缩小区域"}
							var xmin:=INF; var xmax:=-INF; var zmin:=INF; var zmax:=-INF
							for p in piece: xmin=minf(xmin,p.dot(axis)); xmax=maxf(xmax,p.dot(axis)); zmin=minf(zmin,p.dot(along)); zmax=maxf(zmax,p.dot(along))
							for row in range(floori((xmin+f.phase)/f.spacing)-1,ceili((xmax+f.phase)/f.spacing)+1):
								var center: float=row*f.spacing-f.phase
								for band in 4:
									var left: float=center+(band-2)*f.spacing*.21; var right: float=left+f.spacing*.21
									if left>xmax or right<xmin: continue
									var strip:=PackedVector2Array([axis*left+along*(zmin-.01),axis*right+along*(zmin-.01),axis*right+along*(zmax+.01),axis*left+along*(zmax+.01)])
									var cells:=Geometry2D.intersect_polygons(piece,strip); clips+=1
									if clips>MAX_CLIPS: return {"ok":false,"error":"垄沟计算量超出单块预算，请扩大垄距或缩小农田"}
									for cell in cells:
										var indices:=Geometry2D.triangulate_polygon(cell)
										var raised:=PackedVector3Array(); var offsets:=PackedFloat32Array()
										for p in cell:
											var d:=INF
											for i in polygon.size(): d=minf(d,p.distance_to(Geometry2D.get_closest_point_to_segment(p,polygon[i],polygon[(i+1)%polygon.size()])))
											var u:=clampf((p.dot(axis)-left)/(right-left),0.,1.)
											var profile: Array=[0.,.6,1.,.6,0.]
											var height: float=lerpf(profile[band],profile[band+1],u)*f.height*smoothstep(0.,f.margin,d)
											var y: float=(plane.d-plane.normal.x*p.x-plane.normal.z*p.y)/plane.normal.y
											raised.append(Vector3(p.x,y+height,p.y)); offsets.append(height)
										for i in range(0,indices.size(),3):
											var ia:=indices[i]; var ib:=indices[i+1]; var ic:=indices[i+2]
											if maxf(offsets[ia],maxf(offsets[ib],offsets[ic]))<.00001: continue
											var va:=raised[ia]; var vb:=raised[ib]; var vc:=raised[ic]
											if (vc-va).cross(vb-va).y<0: var swap:=vb; vb=vc; vc=swap
											vertices.append(va); vertices.append(vb); vertices.append(vc)
											if vertices.size()/3>MAX_TRIANGLES: return {"ok":false,"error":"单块垄沟超过 48000 三角面，请扩大垄距或拆分农田"}
	return {"ok":true,"vertices":vertices,"triangles":vertices.size()/3,"clips":clips}
static func append_to(mesh: ArrayMesh, record: Dictionary,material: Material) -> void:
	var result:=generate(record)
	if not result.ok:
		push_error("Invalid cultivation geometry: "+str(result.error)); return
	if result.vertices.is_empty(): return
	var st:=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); st.set_material(material)
	var vertices: PackedVector3Array=result.vertices
	for i in range(0,vertices.size(),3):
		var n: Vector3=(vertices[i+2]-vertices[i]).cross(vertices[i+1]-vertices[i]).normalized()
		for j in 3: st.set_normal(n); st.set_uv(Vector2(vertices[i+j].x,vertices[i+j].z)/2.); st.add_vertex(vertices[i+j])
	st.index(); st.generate_tangents(); st.commit(mesh); mesh.surface_set_name(mesh.get_surface_count()-1,"cultivation")
