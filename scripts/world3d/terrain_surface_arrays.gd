extends RefCounted
## Private packed channels; SurfaceTool retains exact MikkTSpace tangents.
## Topology already identifies each top vertex; sides keep generic indexing.
## Every solid cell keeps its underside and every exposed edge keeps its wall.
static var indexed_top_enabled:=true # Diagnostic comparison with the previous bulk top.
var vertices:=PackedVector3Array()
var normals:=PackedVector3Array()
var uvs:=PackedVector2Array()
var at:=0
var tile:=Vector2.ONE
func allocate(count:int)->void:
	vertices.resize(count);normals.resize(count);uvs.resize(count)
func triangle(a:Vector3,b:Vector3,c:Vector3,horizontal:bool)->void:
	var n:Vector3=(c-a).cross(b-a).normalized()
	vertices[at]=a;vertices[at+1]=b;vertices[at+2]=c
	normals[at]=n;normals[at+1]=n;normals[at+2]=n
	if horizontal:
		uvs[at]=Vector2(a.x,a.z)/tile;uvs[at+1]=Vector2(b.x,b.z)/tile;uvs[at+2]=Vector2(c.x,c.z)/tile
	else:
		var across:=Vector3.UP.cross(n)
		uvs[at]=Vector2(a.dot(across),a.y)/tile;uvs[at+1]=Vector2(b.dot(across),b.y)/tile;uvs[at+2]=Vector2(c.dot(across),c.y)/tile
	at+=3
func finish(indexed:bool=false,indices:PackedInt32Array=PackedInt32Array())->Array:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uvs
	if indexed:arrays[Mesh.ARRAY_INDEX]=indices
	var st:=SurfaceTool.new();st.create_from_arrays(arrays)
	if not indexed:st.index()
	st.generate_tangents()
	return st.commit_to_arrays()
static func build(record:Dictionary,grid:PackedVector3Array,grid_normals:PackedVector3Array)->Array:
	var t:Dictionary=record.terrain_mesh;var columns:=int(t.columns);var rows:=int(t.rows);var stride:=columns+1
	var holes:Array=t.holes;var masks:=PackedByteArray();masks.resize(columns*rows)
	var cells:=0;var edges:=0
	# One cheap adjacency pass sizes buffers exactly, including holes. No worst
	# case allocation, shared scratch storage or per-triangle temporary Arrays.
	for z in rows:
		for x in columns:
			var cell:=z*columns+x
			if holes[cell]:continue
			cells+=1;var mask:=0
			if z==0 or holes[cell-columns]:mask|=1;edges+=1
			if x==columns-1 or holes[cell+1]:mask|=2;edges+=1
			if z==rows-1 or holes[cell+columns]:mask|=4;edges+=1
			if x==0 or holes[cell-1]:mask|=8;edges+=1
			masks[cell]=mask
	var top:=new();var sides:=new();var size:Array=record.get("terrain_material",{}).get("tile_size",[2,2])
	top.tile=Vector2(size[0],size[1]);sides.tile=top.tile
	var indexed_top:=indexed_top_enabled
	var top_lookup:=PackedInt32Array();var top_indices:=PackedInt32Array();var top_index_at:=0
	if indexed_top:
		# Use the same first-encounter ordering as SurfaceTool.index(). A grid
		# vertex has one position, seam normal and UV for this entire surface.
		# Holes leave unused grid vertices out of the published arrays.
		top.allocate(mini(grid.size(),cells*6))
		top_lookup.resize(grid.size());top_lookup.fill(-1);top_indices.resize(cells*6)
	else:top.allocate(cells*6)
	sides.allocate((cells+edges)*6)
	var floor_y:float=t.floor*record.size[1]
	for z in rows:
		for x in columns:
			var cell:=z*columns+x
			if holes[cell]:continue
			var v:=z*stride+x
			var ids:=[v,v+1,v+stride+1,v+stride]
			if indexed_top:
				for index:int in ids:
					if top_lookup[index]>=0:continue
					var p:=grid[index];top_lookup[index]=top.at
					top.vertices[top.at]=p;top.normals[top.at]=grid_normals[index];top.uvs[top.at]=Vector2(p.x,p.z)/top.tile;top.at+=1
				var a_id:=top_lookup[v];var b_id:=top_lookup[v+1]
				var c_id:=top_lookup[v+stride+1];var d_id:=top_lookup[v+stride]
				top_indices[top_index_at]=a_id;top_indices[top_index_at+1]=b_id;top_indices[top_index_at+2]=c_id
				top_indices[top_index_at+3]=a_id;top_indices[top_index_at+4]=c_id;top_indices[top_index_at+5]=d_id
				top_index_at+=6
			else:
				for i in [0,1,2,0,2,3]:
					var index:int=ids[i];var p:=grid[index]
					top.vertices[top.at]=p;top.normals[top.at]=grid_normals[index];top.uvs[top.at]=Vector2(p.x,p.z)/top.tile;top.at+=1
			var a:=grid[v];var b:=grid[v+1];var c:=grid[v+stride+1];var d:=grid[v+stride]
			var bottom:=[Vector3(a.x,floor_y,a.z),Vector3(b.x,floor_y,b.z),Vector3(c.x,floor_y,c.z),Vector3(d.x,floor_y,d.z)]
			sides.triangle(bottom[0],bottom[2],bottom[1],true);sides.triangle(bottom[0],bottom[3],bottom[2],true)
			var mask:=int(masks[cell])
			for i in 4:
				if (mask&(1<<i))==0:continue
				var j:=(i+1)%4
				sides.triangle(grid[ids[i]],bottom[i],bottom[j],false);sides.triangle(grid[ids[i]],bottom[j],grid[ids[j]],false)
	if indexed_top:
		top.vertices.resize(top.at);top.normals.resize(top.at);top.uvs.resize(top.at)
	return [top.finish(indexed_top,top_indices),sides.finish()]
