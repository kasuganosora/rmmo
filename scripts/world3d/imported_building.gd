extends RefCounted
## Explicit authored-model contract. Regions are local Godot metres; metadata
## describes real interiors, never an inferred envelope around a facade.
const ROLES=["body","floor","roof","ceiling","stairs","furniture","door","mechanism"]
static var _sources:Dictionary={}
static var _source_mutex:=Mutex.new()
static var single_read_sources_enabled:=true # Profiling control; set before loading workers.

static func bounded(value:Variant,lo:float,hi:float)->bool:
	return (value is float or value is int) and is_finite(float(value)) and value>=lo and value<=hi

static func vector(value:Variant)->bool:
	return value is Array and value.size()==3 and value.all(func(v):return bounded(v,-1000,1000))

static func vec(value:Array)->Vector3:return Vector3(value[0],value[1],value[2])

static func text(value:Variant,limit:int=180)->bool:
	return value is String and not value.is_empty() and value.length()<=limit

static func source_id(value:Variant)->bool:
	if not text(value):return false
	for ch in value:
		if ch not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":return false
	return true

static func same(a:Variant,b:Variant)->bool:
	if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not same(a[i],b[i]):return false
		return true
	if typeof(a)!=typeof(b):return false
	return a==b

static func _descriptor(extras:Array,mesh_extras:Array)->Dictionary:
	var headers:Array=extras.filter(func(e):return e is Dictionary and e.has("rmmo_model_components"))
	if headers.size()!=1:return {}
	var extra:Dictionary=headers[0];var marker:Variant=extra.get("rmmo_model_components")
	if not marker is Dictionary or marker.size()!=1 or not bounded(marker.get("version"),1,1):return {}
	var building:Variant=extra.get("rmmo_building")
	if not building is Dictionary or building.size()!=2 or building.get("version")!=1 or not valid_regions(building.get("regions")):return {}
	var members:Dictionary={};var fixtures:Dictionary={}
	for e:Variant in mesh_extras:
		if not e is Dictionary:return {}
		if not valid_part(e.get("rmmo_part")):return {}
		var id:Variant=e.get("rmmo_source_uuid",e.get("uuid"))
		if not source_id(id) or members.has(id):return {}
		members[id]=e.rmmo_part.duplicate(true)
		if e.has("rmmo_hinge"):
			var h:Variant=e.rmmo_hinge
			if not h is Dictionary or not text(h.get("id")) or not vector(h.get("pivot")) or not bounded(h.get("angle"),-180,180) or not bounded(h.get("open",0),0,1):return {}
			if fixtures.has(h.id) and fixtures[h.id]!=float(h.get("open",0)):return {}
			fixtures[h.id]=float(h.get("open",0))
	if members.is_empty() or members.size()>4096:return {}
	return {"version":1,"regions":building.regions.duplicate(true),"members":members,"fixtures":fixtures}

static func valid_part(part:Variant)->bool:
	return part is Dictionary and part.size()==4 and bounded(part.get("floor"),0,63) and float(part.floor)==floorf(float(part.floor)) and bounded(part.get("floor_y"),-1000,1000) and part.get("role") in ROLES and text(part.get("part"))

static func valid_regions(value:Variant)->bool:
	if not value is Array or value.is_empty() or value.size()>256:return false
	var ids:Dictionary={}
	for r:Variant in value:
		if not r is Dictionary or r.size()!=4 or not text(r.get("id")) or ids.has(r.id):return false
		if not bounded(r.get("floor"),0,63) or float(r.floor)!=floorf(float(r.floor)) or not vector(r.get("min")) or not vector(r.get("max")):return false
		if not AABB(vec(r.min),vec(r.max)-vec(r.min)).has_volume():return false
		for i in 3:
			if r.max[i]<=r.min[i]:return false
		ids[r.id]=true
	return true

static func opted(root:Node)->bool:
	var nodes:Array[Node]=[root];nodes.append_array(root.find_children("*","",true,false))
	return nodes.any(func(n):return n.get_meta("extras",{}) is Dictionary and n.get_meta("extras",{}).has("rmmo_model_components"))

static func describe(root:Node)->Dictionary:
	var nodes:Array[Node]=[root];nodes.append_array(root.find_children("*","",true,false))
	return describe_nodes(nodes)

static func describe_nodes(nodes:Array[Node])->Dictionary:
	var extras:Array=[];var meshes:Array=[]
	for node:Node in nodes:
		var extra:Variant=node.get_meta("extras",{})
		extras.append(extra)
		if node is MeshInstance3D and node.mesh!=null:meshes.append(extra)
	return _descriptor(extras,meshes)

static func source_descriptor(path:String,digest:String)->Dictionary:
	_source_mutex.lock();var cached:Dictionary=_sources.get(digest,{}).duplicate(true);_source_mutex.unlock()
	if not cached.is_empty():return cached
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()<28:return {}
	if file.get_32()!=0x46546c67 or file.get_32()!=2 or file.get_32()!=file.get_length():return {}
	var length:=file.get_32()
	if file.get_32()!=0x4e4f534a or length<4 or length>4*1024*1024 or length+28>file.get_length():return {}
	var data:Variant=JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
	var bin_size:=file.get_32()
	if file.get_32()!=0x004e4942 or file.get_position()+bin_size!=file.get_length():return {}
	file.close()
	var descriptor:=_source_descriptor_json(data,bin_size)
	if descriptor.is_empty() or FileAccess.get_sha256(path)!=digest:return {}
	descriptor.source_sha=digest
	_cache_source(descriptor,digest)
	return descriptor

## Read current source identity and annotations from one authenticated stream.
## Keep only the bounded JSON chunk, never the whole geometry/image payload.
## A digest-keyed descriptor cache does not authorize skipping the file read.
static func read_source_descriptor(path:String,expected_digest:String="")->Dictionary:
	if not single_read_sources_enabled:
		var digest:=FileAccess.get_sha256(path)
		if digest.is_empty() or (not expected_digest.is_empty() and digest!=expected_digest):return {}
		return source_descriptor(path,digest)
	var began:=Time.get_ticks_usec()
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()<28:return {}
	var size:=file.get_length()
	var header:=file.get_buffer(20)
	if header.size()!=20 or header.decode_u32(0)!=0x46546c67 or header.decode_u32(4)!=2 or header.decode_u32(8)!=size or header.decode_u32(16)!=0x4e4f534a:return {}
	var length:=header.decode_u32(12)
	if length<4 or length>4*1024*1024 or length+28>size:return {}
	var json_bytes:=file.get_buffer(length)
	var bin_header:=file.get_buffer(8)
	if json_bytes.size()!=length or bin_header.size()!=8 or file.get_error()!=OK:return {}
	var bin_size:=bin_header.decode_u32(0)
	if bin_header.decode_u32(4)!=0x004e4942 or file.get_position()+bin_size!=size:return {}
	var hash_:=HashingContext.new()
	if hash_.start(HashingContext.HASH_SHA256)!=OK or hash_.update(header)!=OK or hash_.update(json_bytes)!=OK or hash_.update(bin_header)!=OK:return {}
	var remaining:=bin_size;var chunks:=0
	while remaining>0:
		var count:=mini(4*1024*1024,remaining)
		var bytes:=file.get_buffer(count)
		if bytes.size()!=count or file.get_error()!=OK or hash_.update(bytes)!=OK:return {}
		remaining-=count;chunks+=1
		bytes=PackedByteArray()
	if file.get_length()!=size or file.get_position()!=size or file.get_error()!=OK:return {}
	file.close()
	var digest:=hash_.finish().hex_encode()
	preload("res://scripts/world3d/load_trace.gd").elapsed("imported.source_read",began,{"path":path,"bytes":size,"binary_chunks":chunks})
	if digest.length()!=64 or (not expected_digest.is_empty() and digest!=expected_digest):return {}
	_source_mutex.lock();var cached:Dictionary=_sources.get(digest,{}).duplicate(true);_source_mutex.unlock()
	if not cached.is_empty():return cached
	var descriptor:=_source_descriptor_json(JSON.parse_string(json_bytes.get_string_from_utf8()),bin_size)
	if descriptor.is_empty():return {}
	descriptor.source_sha=digest
	_cache_source(descriptor,digest)
	return descriptor

static func _source_descriptor_json(data:Variant,bin_size:int)->Dictionary:
	if not data is Dictionary or not preload("res://scripts/world3d/asset_bounds_manifest.gd").from_json(data,bin_size).get("known",false):return {}
	var pending:Array=data.scenes[int(data.get("scene",0))].get("nodes",[]).duplicate();var extras:Array=[];var meshes:Array=[];var cursor:=0
	while cursor<pending.size():
		var node:Dictionary=data.nodes[int(pending[cursor])];cursor+=1
		extras.append(node.get("extras",{}))
		if node.has("mesh"):meshes.append(node.get("extras",{}))
		pending.append_array(node.get("children",[]))
	return _descriptor(extras,meshes)

static func _cache_source(descriptor:Dictionary,digest:String)->void:
	_source_mutex.lock()
	if _sources.size()>=32:_sources.clear()
	_sources[digest]=descriptor.duplicate(true);_source_mutex.unlock()

static func verify_source(record:Dictionary)->bool:
	if not record.has("model_building"):return true
	if not valid_record(record):return false
	var descriptor:=read_source_descriptor(str(record.get("asset_path","")),record.model_building.source_sha)
	return not descriptor.is_empty() and same(descriptor,record.model_building)

static func valid_descriptor(d:Variant)->bool:
	if not d is Dictionary or d.size()!=5 or d.get("version")!=1 or not valid_regions(d.get("regions")):return false
	var sha:Variant=d.get("source_sha")
	if not sha is String or sha.length()!=64:return false
	for ch in sha:
		if ch not in "0123456789abcdef":return false
	if not d.get("members") is Dictionary or d.members.is_empty() or d.members.size()>4096:return false
	var names:Dictionary={}
	for path:Variant in d.members:
		if not source_id(path) or not valid_part(d.members[path]):return false
		var name:String=path
		if names.has(name):return false
		names[name]=true
	if not d.get("fixtures") is Dictionary or d.fixtures.size()>256:return false
	for id:Variant in d.fixtures:
		if not text(id) or not bounded(d.fixtures[id],0,1):return false
	return true

static func valid_record(record:Dictionary)->bool:
	if not record.has("model_building"):return not record.has("model_building_states")
	if record.get("kind","asset")!="asset" or not valid_descriptor(record.model_building):return false
	if record.has("model_component_states") or not record.get("model_building_states",{}) is Dictionary:return false
	if not record.get("size") is Array or record.size.size()!=3:return false
	for value in record.size:
		if not bounded(value,.000001,100000):return false
	for id in record.get("model_building_states",{}):
		if not record.model_building.fixtures.has(id):return false
		if not bounded(record.model_building_states[id],0,1):return false
	return true

static func frame(record:Dictionary)->Transform3D:
	return Transform3D(Basis.from_euler(vec(record.rotation)*PI/180).scaled_local(vec(record.size)),vec(record.position))

static func regions(record:Dictionary)->Array:
	var result:Array=[]
	for r:Dictionary in record.model_building.regions:
		result.append({"rect":Rect2(r.min[0],r.min[2],r.max[0]-r.min[0],r.max[2]-r.min[2]),"bottom":float(r.min[1]),"top":float(r.max[1]),"floor":int(r.floor),"id":r.id})
	return result

static func member_ids(record:Dictionary)->Array:
	var result:Array=[]
	for path:String in record.model_building.members:result.append(str(record.uuid)+"__"+path)
	result.sort();return result

static func floor_in_view(record:Dictionary,part:Dictionary,settings:Dictionary)->bool:
	if not settings.isolation:return true
	var y:float=(frame(record)*Vector3(0,float(part.floor_y),0)).y
	return y>=float(settings.base_height)-.001 and y<float(settings.base_height)+float(settings.floor_height)-.001
