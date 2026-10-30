extends RefCounted
## Derived broad phase for immutable runtime geometry. Bodies stay live in
## WorldStream. Mutable public sources retain their coarse spatial contract.
const Candidate=preload("res://scripts/world3d/collision_query_candidate.gd")
const CELL_M:=4.0
const COARSE_M:=32.0
const CACHE_RANGES:=8
var members:Dictionary={}
var levels:Dictionary={}
var ranges:Dictionary={}
var serial:=0
var hits:=0
var misses:=0
var last_candidates:=0
var coverage:=Rect2()
var has_coverage:=false
var coarse_index:Dictionary={}
var revision:=0

func matches(index:Dictionary,version:int)->bool:
	return is_same(index,coarse_index) and revision==version

static func coarse_bounds(spec:Dictionary)->AABB:
	var low:Vector2i=spec.chunk_min;var high:Vector2i=spec.chunk_max
	return AABB(Vector3(low.x*COARSE_M,0,low.y*COARSE_M),Vector3((high.x-low.x+1)*COARSE_M,0,(high.y-low.y+1)*COARSE_M))

func add(spec:Dictionary,box:AABB,immutable:bool)->void:
	# Membership follows the same collision index inclusion rule. Do not bake
	# hostile/native/mode filters into the query result: those are read live.
	if spec.get("extras",{}).get("rmmo_collision","")=="none":return
	if not immutable:box=coarse_bounds(spec)
	elif spec.get("extras",{}).has("fixture"):
		box=spec.get("fixture_sweep_bounds",coarse_bounds(spec))
		# A separate collision mesh may extend beyond the visual hinge sweep.
		# Preserve the original coarse collision coverage for that rarer case.
		if spec.get("collision_mesh",spec.mesh)!=spec.mesh:box=box.merge(coarse_bounds(spec))
	else:
		var solid:Mesh=spec.get("collision_mesh")
		if solid!=null and solid!=spec.mesh:
			var bounds:AABB=AABB(-solid.size*.5,solid.size) if solid is BoxMesh else solid.get_aabb()
			box=box.merge(spec.transform*bounds)
	var entry:=Candidate.new(spec)
	entry.query_envelope=Rect2(box.position.x,box.position.z,box.size.x,box.size.z)
	entry.has_query_envelope=true
	coverage=coverage.merge(entry.query_envelope) if has_coverage else entry.query_envelope
	has_coverage=true
	# Large roads/terrain move to a coarser level instead of duplicating a
	# source into thousands of 4 m cells. This limits storage, not map size.
	entry.low=_cell(entry.query_envelope.position,entry.level)
	entry.high=_cell(entry.query_envelope.end,entry.level)
	while (entry.high.x-entry.low.x+1)*(entry.high.y-entry.low.y+1)>16:
		entry.level*=4.0
		entry.low=_cell(entry.query_envelope.position,entry.level);entry.high=_cell(entry.query_envelope.end,entry.level)
	members[spec.uuid]=entry
	if not levels.has(entry.level):levels[entry.level]={}
	var buckets:Dictionary=levels[entry.level]
	for z in range(entry.low.y,entry.high.y+1):
		for x in range(entry.low.x,entry.high.x+1):
			var key:=Vector2i(x,z)
			if not buckets.has(key):buckets[key]={}
			buckets[key][spec.uuid]=entry
	_invalidate_area(entry.query_envelope)

func merge_prepared(other:RefCounted)->void:
	# The unpublished fragment is donated after validation. No geometry reads
	# or rebuild of existing neighborhoods belongs in the commit transaction.
	if other.members.is_empty():return
	members.merge(other.members)
	for level:float in other.levels:
		if not levels.has(level):levels[level]=other.levels[level];continue
		var buckets:Dictionary=levels[level]
		for key:Vector2i in other.levels[level]:
			if buckets.has(key):buckets[key].merge(other.levels[level][key])
			else:buckets[key]=other.levels[level][key]
	coverage=coverage.merge(other.coverage) if has_coverage else other.coverage;has_coverage=true
	_invalidate_area(other.coverage)

func retire(ids:Dictionary)->void:
	# Drop only cached ranges owning retired entries, before returning control.
	# Unrelated retirement must not rebuild the player's current neighborhood.
	for key:Vector4i in ranges.keys():
		var cached:Dictionary=ranges[key].ids
		var small:Dictionary=ids if ids.size()<cached.size() else cached
		var large:Dictionary=cached if is_same(small,ids) else ids
		for id:String in small:
			if large.has(id):ranges.erase(key);break
	for id:String in ids:
		var entry:Candidate=members.get(id)
		if entry==null:continue
		var buckets:Dictionary=levels[entry.level]
		for z in range(entry.low.y,entry.high.y+1):
			for x in range(entry.low.x,entry.high.x+1):
				var key:=Vector2i(x,z)
				buckets[key].erase(id)
				if buckets[key].is_empty():buckets.erase(key)
		if buckets.is_empty():levels.erase(entry.level)
		members.erase(id)

func _invalidate_area(area:Rect2)->void:
	for key:Vector4i in ranges.keys():
		if ranges[key].envelope.intersects(area,true):ranges.erase(key)

static func _cell(point:Vector2,metres:float)->Vector2i:
	return Vector2i(floori(point.x/metres),floori(point.y/metres))

func candidates(area:Rect2)->Array:
	if not area.position.is_finite() or not area.end.is_finite():return []
	var low:=_cell(area.position,CELL_M);var high:=_cell(area.end,CELL_M)
	var key:=Vector4i(low.x,low.y,high.x,high.y)
	serial+=1
	if ranges.has(key):
		hits+=1;ranges[key].stamp=serial;last_candidates=ranges[key].items.size()
		return ranges[key].items
	misses+=1
	# Cache the entire cell union, never today's exact player footprint.
	var first:=Vector2(low)*CELL_M;var last:=Vector2(high+Vector2i.ONE)*CELL_M
	var seen:Dictionary={};var items:Array=[]
	for level:float in levels:
		# last is the exclusive edge of this cached cell union. Including its
		# next cell adds a needless outer ring (9 cells instead of 4 at level 0).
		var a:=_cell(first,level);var b:=Vector2i(ceili(last.x/level)-1,ceili(last.y/level)-1)
		var buckets:Dictionary=levels[level]
		if (b.x-a.x+1)*(b.y-a.y+1)>buckets.size():
			for cell:Vector2i in buckets:
				if cell.x<a.x or cell.y<a.y or cell.x>b.x or cell.y>b.y:continue
				_collect(buckets[cell],seen,items)
		else:
			for z in range(a.y,b.y+1):
				for x in range(a.x,b.x+1):
					var cell:=Vector2i(x,z)
					if buckets.has(cell):_collect(buckets[cell],seen,items)
	last_candidates=items.size()
	# Broad one-off requests remain correct without retaining town-sized lists.
	if (high.x-low.x+1)*(high.y-low.y+1)<=16:
		if ranges.size()>=CACHE_RANGES:
			var oldest:Vector4i=ranges.keys()[0]
			for other:Vector4i in ranges:
				if ranges[other].stamp<ranges[oldest].stamp:oldest=other
			ranges.erase(oldest)
		ranges[key]={"items":items,"stamp":serial,"ids":seen,"envelope":Rect2(first,last-first)}
	return items

static func _collect(bucket:Dictionary,seen:Dictionary,items:Array)->void:
	for id:String in bucket:
		if seen.has(id):continue
		seen[id]=true;items.append(bucket[id])

func snapshot()->Dictionary:
	var cells:=0;var refs:=0
	for buckets:Dictionary in levels.values():
		cells+=buckets.size()
		for bucket:Dictionary in buckets.values():refs+=bucket.size()
	return {"members":members.size(),"levels":levels.size(),"cells":cells,"references":refs,"ranges":ranges.size(),"hits":hits,"misses":misses,"last_candidates":last_candidates}
