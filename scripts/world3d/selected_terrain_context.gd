extends RefCounted
## Private worker preparation for white geometry. Query the requested seams;
## neighboring tiles contribute only coincident, compatible boundary normals.
## No persistent cache, source mutation, Image, Node or RenderingServer access.
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Neighbors=preload("res://scripts/world3d/terrain_neighbors.gd")
static var enabled:=true

static func prepare(records:Array,requested:Dictionary)->Dictionary:
	var sources:Dictionary={};var targets:Dictionary={};var points:Dictionary={}
	var work:={"boundary_positions":0,"boundary_normals":0,"contexts":0,"candidate_tiles":0}
	for record:Dictionary in records:
		if not record.has("terrain_mesh") or absf(record.rotation[0])>.00001 or absf(record.rotation[2])>.00001:continue
		sources[str(record.uuid)]=record
	for id:String in sources:
		if not requested.has(id):continue
		var record:Dictionary=sources[id];var world:=Terrain.transform(record)
		var edges:Array=[]
		for grid:Vector2i in Terrain.boundary(record.terrain_mesh):
			if not _solid(record.terrain_mesh,grid):continue
			var key:=Vector3i((world*Terrain.point(record,grid.x,grid.y)*1000.).round())
			var edge:={"id":id,"key":key,"at":grid.y*(int(record.terrain_mesh.columns)+1)+grid.x,"n":world.basis*Terrain.normal(record,grid.x,grid.y)}
			edges.append(edge);points[key]=[];work.boundary_positions+=1;work.boundary_normals+=1
		targets[id]={"edges":edges,"inverse":world.basis.inverse(),"compatible":{}}
	# Retain source order and z-major boundary order, exactly as the general
	# context's sorted buckets. Shared corners must sum in that same order.
	for id:String in sources:
		var compatible_target:=false
		for target:String in targets:
			if target!=id and Neighbors.compatible(sources[target],sources[id]):
				targets[target].compatible[id]=true;compatible_target=true
		if targets.has(id):
			for edge:Dictionary in targets[id].edges:points[edge.key].append(edge)
			continue
		if not compatible_target:continue
		work.candidate_tiles+=1
		var record:Dictionary=sources[id];var world:=Terrain.transform(record)
		for grid:Vector2i in Terrain.boundary(record.terrain_mesh):
			if not _solid(record.terrain_mesh,grid):continue
			var key:=Vector3i((world*Terrain.point(record,grid.x,grid.y)*1000.).round());work.boundary_positions+=1
			if not points.has(key):continue
			points[key].append({"id":id,"n":world.basis*Terrain.normal(record,grid.x,grid.y)})
			work.boundary_normals+=1
	var data:Dictionary={}
	for id:String in targets:
		var target:Dictionary=targets[id];var normals:Dictionary={};var joins:Dictionary={}
		for edge:Dictionary in target.edges:
			var sum:Vector3=edge.n;var count:=1
			for other:Dictionary in points[edge.key]:
				if not target.compatible.has(other.id):continue
				sum+=other.n;count+=1;joins[other.id]=true
			if count>1:normals[edge.at]=target.inverse*sum.normalized()
		var record:Dictionary=sources[id];var step:=Vector2(record.size[0]/record.terrain_mesh.columns,record.size[2]/record.terrain_mesh.rows)
		var pad:=Vector2i(clampi(ceili(8./step.x)+1,1,33),clampi(ceili(8./step.y)+1,1,33))
		var neighbors:Array=joins.keys();neighbors.sort()
		# Chunk publication already discards the edit-only signature. Do not
		# deep-copy every neighbor's complete heightfield just to discard it.
		data[id]={"signature":[],"normals":normals,"padding":Vector2(pad),"neighbors":neighbors}
	work.contexts=data.size()
	return {"data":data,"work":work}

static func _solid(t:Dictionary,grid:Vector2i)->bool:
	return Terrain.solid(t,grid.x-1,grid.y-1) or Terrain.solid(t,grid.x,grid.y-1) or Terrain.solid(t,grid.x-1,grid.y) or Terrain.solid(t,grid.x,grid.y)
