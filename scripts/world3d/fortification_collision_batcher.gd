extends Node3D
## Exact static triangles in bounded collision groups. No authoring records change.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Geometry=preload("res://scripts/world3d/ground_batch_geometry.gd")
const MAX_TRIANGLES=16384
const MAX_MEMBERS=128
const CACHE_TRIANGLES=262144
const CACHE_GROUPS=64
var groups: Dictionary={}
var rebuild_count:=0
var last_sync_ms:=0.
var max_group_ms:=0.
var profile: Dictionary={}
var _shape_cache: Dictionary={}
var _cache_triangles:=0
var cache_hits:=0
var cache_misses:=0

static func candidate(record: Dictionary) -> bool:
	for field in ["target_path","npc_id","node_id"]:
		if not str(record.get(field,"")).is_empty(): return false
	return record.has("fortification") and Geometry.candidate(record)

static func hit_uuid(hit: Dictionary) -> String:
	if hit.is_empty(): return ""
	var body: Object=hit.collider
	if not body.has_meta("fortification_collision_ranges"): return str(body.get_meta("uuid",""))
	var face: int=int(hit.get("face_index",-1))
	if face<0: return ""
	var ranges: Array=body.get_meta("fortification_collision_ranges")
	var low:=0; var high:=ranges.size()
	while low<high:
		var mid: int=(low+high)/2
		if face<int(ranges[mid][0]): high=mid
		else: low=mid+1
	return str(ranges[low][1]) if low<ranges.size() else ""

static func entry(mesh: Mesh,pose: Transform3D,uuid: String,extras: Dictionary) -> Dictionary:
	return {"cpu":Cpu.capture(mesh),"transform":pose,"uuid":uuid,"surface_id":str(extras.get("surface_id","block")),"collision":str(extras.get("rmmo_collision","block"))}

func _ready() -> void:
	name="FortificationCollisionBatches"; set_meta("stream_instance",true)

func clear() -> void:
	for group: Dictionary in groups.values(): group.body.free()
	groups.clear()
	_shape_cache.clear(); _cache_triangles=0

func _remember(key: String,value: Dictionary) -> void:
	if value.triangles>CACHE_TRIANGLES: return
	while not _shape_cache.is_empty() and (_shape_cache.size()>=CACHE_GROUPS or _cache_triangles+value.triangles>CACHE_TRIANGLES):
		var oldest: String=_shape_cache.keys()[0]; _cache_triangles-=_shape_cache[oldest].triangles; _shape_cache.erase(oldest)
	_shape_cache[key]=value; _cache_triangles+=value.triangles

func sync(entries: Array) -> void:
	var started:=Time.get_ticks_usec(); var desired: Dictionary={}
	profile={"prepare_ms":0.,"faces_us":0,"shape_us":0,"install_us":0}
	entries=entries.duplicate()
	entries.sort_custom(func(a,b):return a.uuid<b.uuid)
	for source: Dictionary in entries:
		var extent: Vector3=source.cpu.bounds.size
		var cell:=maxf(32.,pow(2.,ceil(log(maxf(1.,maxf(extent.x,extent.z)))/log(2.))))
		var center: Vector3=source.transform.origin
		var triangles: int=source.cpu.collision_faces().size()/3
		var base:=var_to_str([floor(center.x/cell),floor(center.z/cell),cell,source.surface_id,source.collision])
		var key:=base+":0"; var bin:=0
		while desired.has(key) and (desired[key].members.size()>=MAX_MEMBERS or desired[key].triangles+triangles>MAX_TRIANGLES): bin+=1; key=base+":"+str(bin)
		if not desired.has(key): desired[key]={"members":[],"signature":[],"triangles":0,"origin":Vector3((floor(center.x/cell)+.5)*cell,0,(floor(center.z/cell)+.5)*cell)}
		desired[key].members.append(source); desired[key].triangles+=triangles
		desired[key].signature.append([source.uuid,source.cpu.geometry_key(),source.transform])
	for key: String in groups.keys():
		if not desired.has(key): groups[key].body.free(); groups.erase(key)
	profile.prepare_ms=(Time.get_ticks_usec()-started)/1000.
	for key: String in desired:
		var group: Dictionary=desired[key]
		if groups.has(key) and groups[key].signature==group.signature: continue
		var begin:=Time.get_ticks_usec(); var ranges: Array=[]
		var digest:=HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(var_to_bytes([group.origin,group.signature]))
		var cache_key:=digest.finish().hex_encode(); var shape: ConcavePolygonShape3D
		if _shape_cache.has(cache_key):
			var cached: Dictionary=_shape_cache[cache_key]; shape=cached.shape; ranges=cached.ranges
			_shape_cache.erase(cache_key); _shape_cache[cache_key]=cached; cache_hits+=1
		else:
			cache_misses+=1; var faces:=PackedVector3Array()
			for source: Dictionary in group.members:
				# World quantization before rebasing preserves exact tower fan centers.
				faces.append_array(Transform3D(Basis.IDENTITY,-group.origin)*(source.transform*source.cpu.collision_faces())); ranges.append([faces.size()/3,source.uuid])
			var prepared:=Time.get_ticks_usec(); profile.faces_us+=prepared-begin
			shape=ConcavePolygonShape3D.new(); shape.set_faces(faces)
			profile.shape_us+=Time.get_ticks_usec()-prepared
			_remember(cache_key,{"shape":shape,"ranges":ranges,"triangles":group.triangles})
		var mark:=Time.get_ticks_usec()
		var collision:=CollisionShape3D.new(); collision.shape=shape
		var body:=StaticBody3D.new(); body.add_child(collision)
		body.set_meta("fortification_collision_ranges",ranges); body.set_meta("surface_id",group.members[0].surface_id); body.set_meta("kind","box")
		body.transform=global_transform.affine_inverse()*Transform3D(Basis.IDENTITY,group.origin)
		add_child(body)
		# Install the replacement before discarding the previous broad-phase proxy.
		if groups.has(key): groups[key].body.free()
		group.body=body; groups[key]=group; rebuild_count+=1
		profile.install_us+=Time.get_ticks_usec()-mark
		max_group_ms=maxf(max_group_ms,(Time.get_ticks_usec()-begin)/1000.)
	last_sync_ms=(Time.get_ticks_usec()-started)/1000.

func stats() -> Dictionary:
	var count:=0; var triangles:=0
	for group: Dictionary in groups.values(): count+=group.members.size(); triangles+=group.triangles
	return {"source_objects":count,"bodies":groups.size(),"shapes":groups.size(),"triangles":triangles,"rebuild_count":rebuild_count,"last_sync_ms":last_sync_ms,"max_group_ms":max_group_ms,"profile":profile.duplicate(),"shape_cache_groups":_shape_cache.size(),"shape_cache_triangles":_cache_triangles,"shape_cache_hits":cache_hits,"shape_cache_misses":cache_misses}
