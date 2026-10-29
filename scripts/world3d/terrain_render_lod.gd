extends RefCounted
## Render-only regular heightfield indices. Every external boundary segment is
## retained, so adjacent tiles can select unrelated LODs without T junctions.
static var enabled:=true
const STEPS=[2,4,8]
static func eligible(record:Dictionary)->bool:
	if not enabled or not record.has("terrain_mesh") or record.has("surface_paint"):return false
	var t:Dictionary=record.terrain_mesh
	return int(t.columns)*int(t.rows)>=256 and not t.holes.has(true)
static func derive(record:Dictionary,arrays:Array)->Dictionary:
	if not eligible(record):return {}
	var t:Dictionary=record.terrain_mesh;var columns:=int(t.columns);var rows:=int(t.rows)
	if columns*rows<256 or t.holes.has(true):return {}
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var lookup:Dictionary={}
	for i in vertices.size():
		var p:Vector3=vertices[i]
		var cell:=Vector2i(roundi((p.x/record.size[0]+.5)*columns),roundi((p.z/record.size[2]+.5)*rows))
		if cell.x<0 or cell.x>columns or cell.y<0 or cell.y>rows:return {}
		if absf(p.x-(float(cell.x)/columns-.5)*record.size[0])>maxf(.00001,record.size[0]*.000001) or absf(p.z-(float(cell.y)/rows-.5)*record.size[2])>maxf(.00001,record.size[2]*.000001):return {}
		if lookup.has(cell):return {} # Split or custom topology stays exact.
		lookup[cell]=i
	if lookup.size()!=(columns+1)*(rows+1):return {}
	var levels:Array=[];var errors:Array=[]
	for step:int in STEPS:
		var indices:=PackedInt32Array();var bound:=0.
		for z0 in range(0,rows,step):
			for x0 in range(0,columns,step):
				var x1:=mini(x0+step,columns);var z1:=mini(z0+step,rows)
				if x1-x0<2 or z1-z0<2:
					for z in range(z0,z1):
						for x in range(x0,x1):
							for p:Vector2i in [Vector2i(x,z),Vector2i(x+1,z),Vector2i(x+1,z+1),Vector2i(x,z),Vector2i(x+1,z+1),Vector2i(x,z+1)]:indices.append(lookup[p])
					continue
				var edge:Array[Vector2i]=[Vector2i(x0,z0)]
				if z0==0:
					for x in range(x0+1,x1):edge.append(Vector2i(x,z0))
				edge.append(Vector2i(x1,z0))
				if x1==columns or (columns%step==1 and x1==columns-1):
					for z in range(z0+1,z1):edge.append(Vector2i(x1,z))
				edge.append(Vector2i(x1,z1))
				if z1==rows or (rows%step==1 and z1==rows-1):
					for x in range(x1-1,x0,-1):edge.append(Vector2i(x,z1))
				edge.append(Vector2i(x0,z1))
				if x0==0:
					for z in range(z1-1,z0,-1):edge.append(Vector2i(x0,z))
				var centre:Vector2i=Vector2i((x0+x1)/2,(z0+z1)/2)
				for i in edge.size():indices.append_array(PackedInt32Array([lookup[edge[i]],lookup[edge[(i+1)%edge.size()]],lookup[centre]]))
				# Both triangulations interpolate samples inside this patch. Relative
				# to one affine plane each lies within max_deviation, so their
				# difference is bounded by twice that, also bounded by height range.
				var a:Vector3=vertices[lookup[Vector2i(x0,z0)]];var b:Vector3=vertices[lookup[Vector2i(x1,z0)]];var c:Vector3=vertices[lookup[Vector2i(x0,z1)]]
				var low:=INF;var high:=-INF;var deviation:=0.
				for z in range(z0,z1+1):
					for x in range(x0,x1+1):
						var y:float=vertices[lookup[Vector2i(x,z)]].y;low=minf(low,y);high=maxf(high,y)
						var expected:float=a.y+(b.y-a.y)*float(x-x0)/(x1-x0)+(c.y-a.y)*float(z-z0)/(z1-z0)
						deviation=maxf(deviation,absf(y-expected))
				bound=maxf(bound,maxf(.00002,minf(high-low,deviation*2.)))
		levels.append(indices);errors.append(bound)
	return {"indices":levels,"errors":errors}

static func update(map_root:Node,eye:Vector3)->void:
	var batcher:=map_root.get_node_or_null("GroundRenderBatches")
	if batcher==null:return
	for id:int in batcher.terrain_lod_visuals.keys():
		var visual:Node=batcher.terrain_lod_visuals[id].get_ref()
		if not is_instance_valid(visual):batcher.terrain_lod_visuals.erase(id);continue
		if visual.mesh==null:continue
		var box:AABB=visual.global_transform*visual.mesh.get_aabb()
		var nearest:Vector3=eye.clamp(box.position,box.end)
		visual.lod_bias=2. if enabled and nearest.distance_to(eye)>160. else 1000000.
