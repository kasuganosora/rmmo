extends RefCounted
## Document-owned broad phase. Only layout changes rebuild the adjacency graph.
## Authoring order and the existing exact adjacency predicate remain authoritative.
const T=preload("res://scripts/world3d/terrain_surface.gd")
const Batch=preload("res://scripts/world3d/terrain_stroke_batch.gd")
const CELL=128.
var signature:Array=[]
var links:Dictionary={}
var builds:=0
var exact_tests:=0
var sources:Dictionary={}
var buckets:Dictionary={}
var regions:Dictionary={}
var broad:Array=[]
var ranks:Dictionary={}
func update(records:Array)->void:
	var next:Array=[];var selected:Dictionary={}
	for r:Dictionary in records:
		if not r.has("terrain_mesh"):continue
		selected[str(r.uuid)]=r;next.append([r.uuid,r.position,r.rotation,r.size])
	if next==signature:return
	signature=next.duplicate(true);builds+=1;exact_tests=0;links.clear()
	sources.clear()
	for id:String in selected:
		var r:Dictionary=selected[id];sources[id]={"uuid":id,"position":r.position.duplicate(),"rotation":r.rotation.duplicate(),"size":r.size.duplicate()}
	buckets.clear();regions.clear();broad.clear();ranks.clear()
	for id:String in selected:
		var r:Dictionary=selected[id];var pose:=T.transform(r)
		var box:=AABB(pose*Vector3(-r.size[0]*.5,0,-r.size[2]*.5),Vector3.ZERO)
		for x in [-1,1]:
			for z in [-1,1]:box=box.expand(pose*Vector3(x*r.size[0]*.5,0,z*r.size[2]*.5))
		box=box.grow(.01+maxf(r.size[0],r.size[2])*.00002)
		var lo:=Vector2i(floori(box.position.x/CELL),floori(box.position.z/CELL))
		var hi:=Vector2i(floori(box.end.x/CELL),floori(box.end.z/CELL))
		if r.rotation[0]!=0 or r.rotation[2]!=0 or maxf(absf(r.position[0]),absf(r.position[2]))>16384. or maxf(r.size[0],r.size[2])>16384. or (hi.x-lo.x+1)*(hi.y-lo.y+1)>64:
			broad.append(id);continue
		var keys:Array=[]
		for z in range(lo.y,hi.y+1):
			for x in range(lo.x,hi.x+1):
				var key:=Vector2i(x,z);keys.append(key)
				if not buckets.has(key):buckets[key]=[]
				buckets[key].append(id)
		regions[id]=keys
	var order:Array=selected.keys()
	for i in order.size():ranks[order[i]]=i
func neighbors(id:String)->Array:
	if links.has(id):return links[id]
	var candidates:Dictionary={}
	if id in broad:
		for other:String in sources:candidates[other]=true
	else:
		for key:Vector2i in regions.get(id,[]):
			for other:String in buckets[key]:candidates[other]=true
		for other:String in broad:candidates[other]=true
	var sorted:Array=candidates.keys();sorted.sort_custom(func(a,b):return ranks[a]<ranks[b])
	var result:Array=[]
	for other:String in sorted:
		if id==other:continue
		var r:Dictionary=sources[other]
		if absf(r.rotation[0])>.0001 or absf(r.rotation[2])>.0001:continue
		exact_tests+=1
		if Batch.adjacent(sources[id],r):result.append(other)
	links[id]=result
	return result
func connected(records:Array,seed:Dictionary)->Array:
	update(records)
	var by_id:Dictionary={}
	for r:Dictionary in records:by_id[str(r.uuid)]=r
	var result:Array=[seed];var seen:Dictionary={str(seed.uuid):true};var cursor:=0
	while cursor<result.size() and result.size()<=256:
		var id:String=str(result[cursor].uuid);cursor+=1
		for other:String in neighbors(id):
			if not seen.has(other):seen[other]=true;result.append(by_id[other])
	return result
