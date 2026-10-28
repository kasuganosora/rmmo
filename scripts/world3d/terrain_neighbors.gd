extends RefCounted
## Derived document-owned normals and height halos, never authoring/collision edits.
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
var data: Dictionary={}
var signature: Array=[]
var sources: Dictionary={}
var edge_cache:Dictionary={}
var point_index:Dictionary={}
var dependents:Dictionary={}
var last_work:Dictionary={}

static func compatible(a: Dictionary,b: Dictionary) -> bool:
	var ta:=Terrain.transform(a); var tb:=Terrain.transform(b)
	if not ta.basis.is_equal_approx(tb.basis): return false
	var sa:=Vector2(a.size[0]/a.terrain_mesh.columns,a.size[2]/a.terrain_mesh.rows)
	var sb:=Vector2(b.size[0]/b.terrain_mesh.columns,b.size[2]/b.terrain_mesh.rows)
	if not sa.is_equal_approx(sb): return false
	var offset:=ta.affine_inverse()*tb.origin
	var span:=Vector2(a.size[0]+b.size[0],a.size[2]+b.size[2])*.5
	return (absf(absf(offset.x)-span.x)<.001 and absf(offset.z)<=span.y+.001) or (absf(absf(offset.z)-span.y)<.001 and absf(offset.x)<=span.x+.001)
func update(records: Array, parallel:bool=false) -> Array[String]:
	return _update(records,parallel)

## A private chunk job reads neighboring edges but publishes only its requested
## tiles. Editing still uses update(), retaining the full incremental context.
func prepare_selected(records:Array,requested:Dictionary)->void:
	assert(data.is_empty() and sources.is_empty())
	if requested.is_empty():
		last_work={"boundary_vertices":0,"contexts":0,"records":0};return
	_update(records,false,requested)

func _update(records:Array,parallel:bool,requested:Dictionary={})->Array[String]:
	var next: Array=[]; var selected: Dictionary={}
	for r in records:
		if not r.has("terrain_mesh") or absf(r.rotation[0])>.00001 or absf(r.rotation[2])>.00001: continue
		selected[str(r.uuid)]=r; next.append([r.uuid,r.position,r.rotation,r.size,r.terrain_mesh])
	if signature==next:return []
	last_work={"boundary_vertices":0,"contexts":0,"records":selected.size()}
	var dirty:Dictionary={};var affected:Dictionary={}
	for id:String in edge_cache:
		var old:Dictionary=edge_cache[id]
		var r:Dictionary=selected.get(id,{})
		if not r.is_empty() and old.signature==[r.position,r.rotation,r.size,r.terrain_mesh]:continue
		dirty[id]=true;affected[id]=true
		for other:String in dependents.get(id,[]):affected[other]=true
		for edge:Dictionary in old.edges:
			var bucket:Array=point_index[edge.key]
			for v:Dictionary in bucket:affected[v.id]=true
			bucket.erase(edge)
			if bucket.is_empty():point_index.erase(edge.key)
	for id:String in dirty:edge_cache.erase(id)
	signature=next.duplicate(true); sources=selected
	var ranks:Dictionary={};var rank:=0
	for id:String in sources:
		ranks[id]=rank;rank+=1
		if edge_cache.has(id):continue
		dirty[id]=true;affected[id]=true
		var r:Dictionary=sources[id];var t:Dictionary=r.terrain_mesh;var world:=Terrain.transform(r)
		var edges:Array=[]
		for grid:Vector2i in Terrain.boundary(t):
			var x:=grid.x;var z:=grid.y
			if not (Terrain.solid(t,x-1,z-1) or Terrain.solid(t,x,z-1) or Terrain.solid(t,x-1,z) or Terrain.solid(t,x,z)):continue
			var key:=Vector3i((world*Terrain.point(r,x,z)*1000.).round())
			var edge:={"id":id,"key":key,"at":z*(int(t.columns)+1)+x,"n":world.basis*Terrain.normal(r,x,z)}
			if not point_index.has(key):point_index[key]=[]
			point_index[key].append(edge);edges.append(edge);last_work.boundary_vertices+=1
			for other:Dictionary in point_index[key]:affected[other.id]=true
		edge_cache[id]={"signature":[r.position,r.rotation,r.size,r.terrain_mesh].duplicate(true),"edges":edges}
	var joins:Dictionary={};var normals:Dictionary={}
	# Query only buckets belonging to invalidated boundaries. Unchanged edge
	# descriptors and halo dependencies survive height-only edits elsewhere.
	for id:String in sources:
		joins[id]={};normals[id]={}
		if not requested.is_empty() and not requested.has(id):continue
		if not affected.has(id) and data.has(id):
			for other:String in data[id].neighbors:joins[id][other]=true
			normals[id]=data[id].normals;continue
		var pairs:Dictionary={}
		for edge:Dictionary in edge_cache[id].edges:
			var bucket:Array=point_index[edge.key].duplicate()
			bucket.sort_custom(func(a,b):return a.at<b.at if a.id==b.id else ranks[a.id]<ranks[b.id])
			var sum:Vector3=edge.n;var count:=1
			for other:Dictionary in bucket:
				if id==other.id:continue
				if not pairs.has(other.id):pairs[other.id]=compatible(sources[id],sources[other.id])
				if not pairs[other.id]:continue
				sum+=other.n;count+=1;joins[id][other.id]=true
			if count>1:normals[id][edge.at]=Terrain.transform(sources[id]).basis.inverse()*sum.normalized()
	var changed: Array[String]=[]; var fresh:={}; var pending:Array=[]
	for id: String in sources:
		if not requested.is_empty() and not requested.has(id):continue
		var r: Dictionary=sources[id]; var neighbors: Array=joins[id].keys(); neighbors.sort()
		var local_signature: Array=[r.position,r.rotation,r.size,r.terrain_mesh]
		for other: String in neighbors:
			var n: Dictionary=sources[other]; local_signature.append([n.position,n.rotation,n.size,n.terrain_mesh])
		if data.has(id) and data[id].signature==local_signature: fresh[id]=data[id]; continue
		last_work.contexts+=1
		pending.append({"id":id,"record":r,"neighbors":neighbors,"signature":local_signature,"normals":normals[id],"result":{}})
		changed.append(id)
	# Workers only own their output entry; source records remain immutable.
	var buckets:Array=[[],[],[],[]];var workers:Array[Thread]=[]
	for i in pending.size():buckets[i%4].append(pending[i])
	for bucket:Array in buckets:
		var task:=func():
			for entry:Dictionary in bucket:entry.result=_patch_context(entry.record,sources,entry.normals,entry.neighbors,entry.signature)
		var worker:=Thread.new()
		if parallel and bucket.size()>0 and worker.start(task)==OK:workers.append(worker)
		else:task.call()
	for worker:Thread in workers:worker.wait_to_finish()
	for entry:Dictionary in pending:fresh[entry.id]=entry.result
	for id: String in data:
		if not fresh.has(id): changed.append(id)
	dependents.clear()
	for id:String in fresh:
		for other:String in fresh[id].neighbors:
			if not dependents.has(other):dependents[other]=[]
			dependents[other].append(id)
	data=fresh
	return changed

static func _patch_context(r:Dictionary,sources:Dictionary,normals:Dictionary,neighbors:Array,local_signature:Array)->Dictionary:
	var t: Dictionary=r.terrain_mesh; var step:=Vector2(r.size[0]/t.columns,r.size[2]/t.rows)
	# Maximum material-transition query is 8m, plus an interpolation sample.
	var pad:=Vector2i(clampi(ceili(8./step.x)+1,1,33),clampi(ceili(8./step.y)+1,1,33))
	var width:=int(t.columns)+1+pad.x*2; var height:=int(t.rows)+1+pad.y*2
	var pixels:=PackedFloat32Array(); pixels.resize(width*height)
	var world:=Terrain.transform(r); var adjacent: Array=[]
	for other: String in neighbors: adjacent.append({"record":sources[other],"inverse":Terrain.transform(sources[other]).affine_inverse()})
	for z in height:
		for x in width:
			var gx:=x-pad.x; var gz:=z-pad.y
			var h: float=t.heights[clampi(gz,0,t.rows)*(int(t.columns)+1)+clampi(gx,0,t.columns)]*r.size[1]
			if gx<0 or gz<0 or gx>int(t.columns) or gz>int(t.rows):
				var p:=world*Vector3((gx-float(t.columns)*.5)*step.x,0,(gz-float(t.rows)*.5)*step.y)
				for neighbor: Dictionary in adjacent:
					var local: Vector3=neighbor.inverse*p; var sample:=Terrain.sample(neighbor.record,local)
					if is_finite(sample): h=sample+neighbor.record.position[1]-r.position[1]; break
			pixels[z*width+x]=h
	return {"signature":local_signature.duplicate(true),"normals":normals,"image":Image.create_from_data(width,height,false,Image.FORMAT_RF,pixels.to_byte_array()),"padding":Vector2(pad),"neighbors":neighbors}
