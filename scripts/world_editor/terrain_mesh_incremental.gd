extends RefCounted
## Immutable CPU patching for fixed-topology interior height edits.
## Canonical full mesher remains the fallback for exposed cuts and large edits.
const T=preload("res://scripts/world3d/terrain_surface.gd")
static var enabled:=true
static var last_work:Dictionary={}
static func mapping(r:Dictionary,arrays:Array)->Dictionary:
	if arrays.size()!=2:return {}
	var top:Array=arrays[0];var vertices:PackedVector3Array=top[Mesh.ARRAY_VERTEX]
	var result:Dictionary={};var t:Dictionary=r.terrain_mesh;var stride:=int(t.columns)+1
	for i in vertices.size():
		var p:Vector3=vertices[i];var x:=roundi((p.x/r.size[0]+.5)*t.columns);var z:=roundi((p.z/r.size[2]+.5)*t.rows)
		if x<0 or z<0 or x>int(t.columns) or z>int(t.rows):return {}
		var expected:=T.point(r,x,z)
		if expected!=p:return {}
		var at:=z*stride+x
		if result.has(at):return {} # Unsupported split vertices must not alias.
		result[at]=i
	return result
static func patch(state:Dictionary,r:Dictionary,context:Dictionary)->Dictionary:
	last_work={"incremental":false}
	if not enabled or not state.has("vertex_map") or state.vertex_map.is_empty():return {}
	var previous:Dictionary=state.record;var t:Dictionary=r.terrain_mesh;var stride:=int(t.columns)+1
	var before:Dictionary=previous.terrain_mesh
	if r.size!=previous.size or t.columns!=before.columns or t.rows!=before.rows or t.floor!=before.floor or t.holes!=before.holes:return {}
	if state.normals!=context.get("normals",{}):return {}
	var changed:Dictionary={};var lo:=Vector2i(int(t.columns),int(t.rows));var hi:=Vector2i.ZERO
	for at:int in t.heights.size():
		if t.heights[at]==previous.terrain_mesh.heights[at]:continue
		var x:int=at%stride;var z:int=at/stride
		# An exposed edge changes the side mesh and its indexing/UVs as well.
		if not (T.solid(t,x-1,z-1) and T.solid(t,x,z-1) and T.solid(t,x-1,z) and T.solid(t,x,z)):return {}
		for dz in range(maxi(0,z-1),mini(int(t.rows),z+1)+1):
			for dx in range(maxi(0,x-1),mini(int(t.columns),x+1)+1):
				var key:=dz*stride+dx
				if state.vertex_map.has(key):changed[key]=true;lo=lo.min(Vector2i(dx,dz));hi=hi.max(Vector2i(dx,dz))
	if changed.is_empty():return {"arrays":state.arrays}
	var begin:Vector2i=(lo-Vector2i.ONE).max(Vector2i.ZERO)
	var end:Vector2i=(hi+Vector2i.ONE).min(Vector2i(int(t.columns),int(t.rows)))
	if (end.x-begin.x)*(end.y-begin.y)>int(t.columns)*int(t.rows)/2:return {}
	var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tile:Array=r.get("terrain_material",{}).get("tile_size",[2,2]);var uv_scale:=Vector2(tile[0],tile[1])
	var points:Dictionary={};var normals:Dictionary={}
	for z in range(begin.y,end.y+1):
		for x in range(begin.x,end.x+1):
			var at:=z*stride+x;points[at]=T.point(r,x,z);normals[at]=context.get("normals",{}).get(at,T.normal(r,x,z))
	for z in range(begin.y,end.y):
		for x in range(begin.x,end.x):
			if not T.solid(t,x,z):continue
			var at:=z*stride+x
			for key:int in [at,at+1,at+stride+1,at,at+stride+1,at+stride]:
				var p:Vector3=points[key];tool.set_normal(normals[key]);tool.set_uv(Vector2(p.x,p.z)/uv_scale);tool.add_vertex(p)
	tool.index();tool.generate_tangents()
	var local:Array=tool.commit_to_arrays();var old:Array=state.arrays
	var result:Array=old.duplicate();var top:Array=old[0].duplicate()
	var vertices:PackedVector3Array=top[Mesh.ARRAY_VERTEX].duplicate();var ns:PackedVector3Array=top[Mesh.ARRAY_NORMAL].duplicate();var ts:PackedFloat32Array=top[Mesh.ARRAY_TANGENT].duplicate()
	var found:=0
	for i in local[Mesh.ARRAY_VERTEX].size():
		var p:Vector3=local[Mesh.ARRAY_VERTEX][i];var x:=roundi((p.x/r.size[0]+.5)*t.columns);var z:=roundi((p.z/r.size[2]+.5)*t.rows);var at:=z*stride+x
		if not changed.has(at):continue
		var target:int=state.vertex_map[at]
		vertices[target]=p;ns[target]=local[Mesh.ARRAY_NORMAL][i]
		for k in 4:ts[target*4+k]=local[Mesh.ARRAY_TANGENT][i*4+k]
		found+=1
	if found!=changed.size():return {}
	top[Mesh.ARRAY_VERTEX]=vertices;top[Mesh.ARRAY_NORMAL]=ns;top[Mesh.ARRAY_TANGENT]=ts;result[0]=top
	last_work={"incremental":true,"changed_vertices":changed.size(),"prepared_cells":(end.x-begin.x)*(end.y-begin.y),"total_cells":int(t.columns)*int(t.rows)}
	return {"arrays":result}
