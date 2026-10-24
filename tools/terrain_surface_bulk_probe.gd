extends RefCounted
## Isolated exact-order bulk-call experiment; no production references.
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
static func arrays(record:Dictionary,context:Dictionary={})->Array:
	var t:Dictionary=record.terrain_mesh
	var tile: Array=record.get("terrain_material",{}).get("tile_size",[2,2]); var uv_scale:=Vector2(tile[0],tile[1])
	var top:=SurfaceTool.new(); top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides:=SurfaceTool.new(); sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Each shared grid vertex used to recompute its position/normal for every
	# adjacent cell. Cache once without changing triangle order or paint signatures.
	var grid:=PackedVector3Array(); var grid_normals:=PackedVector3Array()
	var stride:=int(t.columns)+1
	for z in range(int(t.rows)+1):
		for x in stride: grid.append(Terrain.point(record,x,z))
	for z in range(int(t.rows)+1):
		for x in stride:
			var dx:=grid[z*stride+mini(x+1,t.columns)]-grid[z*stride+maxi(x-1,0)]
			var dz:=grid[mini(z+1,t.rows)*stride+x]-grid[maxi(z-1,0)*stride+x]
			grid_normals.append(context.get("normals",{}).get(z*stride+x,dz.cross(dx).normalized()))
	for z in int(t.rows):
		for x in int(t.columns):
			if not Terrain.solid(t,x,z): continue
			var at:=z*stride+x
			var p:=[grid[at],grid[at+1],grid[at+stride+1],grid[at+stride]]
			var normals:=[grid_normals[at],grid_normals[at+1],grid_normals[at+stride+1],grid_normals[at+stride]]
			var uv:=PackedVector2Array()
			for v:Vector3 in p:uv.append(Vector2(v.x,v.z)/uv_scale)
			top.add_triangle_fan(PackedVector3Array(p),uv,PackedColorArray(),PackedVector2Array(),PackedVector3Array(normals))
			var bottom: Array[Vector3]=[]
			for v in p: bottom.append(Vector3(v.x,t.floor*record.size[1],v.z))
			triangle(sides,[bottom[0],bottom[2],bottom[1]],uv_scale,true)
			triangle(sides,[bottom[0],bottom[3],bottom[2]],uv_scale,true)
			var neighbors:=[Vector2i(x,z-1),Vector2i(x+1,z),Vector2i(x,z+1),Vector2i(x-1,z)]
			for i in 4:
				if Terrain.solid(t,neighbors[i].x,neighbors[i].y): continue
				var j: int=(i+1)%4
				triangle(sides,[p[i],bottom[i],bottom[j]],uv_scale,false)
				triangle(sides,[p[i],bottom[j],p[j]],uv_scale,false)
	top.index(); top.generate_tangents()
	sides.index(); sides.generate_tangents()
	var result:Array=[top.commit_to_arrays(),sides.commit_to_arrays()]
	var furrows:=preload("res://scripts/world3d/terrain_furrows.gd").arrays(record)
	if not furrows.is_empty():result.append(furrows)
	return result
static func triangle(st: SurfaceTool, points: Array, tile: Vector2, horizontal: bool) -> void:
	var n: Vector3=(points[2]-points[0]).cross(points[1]-points[0]).normalized()
	var uv:=PackedVector2Array()
	for p:Vector3 in points:uv.append((Vector2(p.x,p.z) if horizontal else Vector2(p.dot(Vector3.UP.cross(n)),p.y))/tile)
	st.add_triangle_fan(PackedVector3Array(points),uv,PackedColorArray(),PackedVector2Array(),PackedVector3Array([n,n,n]))
