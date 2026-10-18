extends RefCounted
## Covered-loading lookahead. Workers own only immutable CPU value snapshots;
## meshes and the byte lease stay on main until every result is consumed/drained.
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const MAX_ITEMS:=16
const MAX_BYTES:=32*1024*1024
var item_limit:=MAX_ITEMS
var byte_limit:=16*1024*1024
var thread_starter:Callable
var _thread:Thread
var _token:RefCounted
var _drainer:Node
var _ready:Dictionary={}
var _charge:=Lease.new()
var _leases:Dictionary=_charge.rows
var _draining:Lease
var profile:Dictionary={"batches":0,"hits":0,"peak_bytes":0,"reserved_bytes":0,"queued":0,"start_failures":0,"cancelled_batches":0}

class Lease extends RefCounted:
	var rows:Dictionary={}
	var bytes:=0
	var drained:=false
	func release()->void:
		rows.clear();bytes=0;drained=true
	func erase(key:String)->void:
		if not rows.has(key):return
		bytes-=int(rows[key].bytes);rows.erase(key)

static func key(source:Mesh,cpu:Mesh,basis:Basis)->String:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.collision_face_prefetch.key") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	return "%d:%d:"%[source.get_instance_id(),cpu.get_instance_id()]+var_to_bytes(basis).hex_encode()

func _update_profile()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.collision_face_prefetch._update_profile") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var draining_bytes:int=_draining.bytes if _draining!=null else 0
	profile.reserved_bytes=_charge.bytes+draining_bytes
	profile.queued=_charge.rows.size()+(_draining.rows.size() if _draining!=null else 0)
	profile.peak_bytes=maxi(int(profile.peak_bytes),int(profile.reserved_bytes))

func poll()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.collision_face_prefetch.poll") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if _draining!=null and _draining.drained:_draining=null
	if _thread==null or _thread.is_alive():_update_profile();return
	# This join is already complete. No main-thread wait for active CPU work.
	var packet:Variant=_thread.wait_to_finish()
	if is_instance_valid(_drainer):_drainer.forget(_thread)
	_thread=null
	if _token!=null:
		_token.remove_meta("admission_release");_token.remove_meta("admission_owner")
	_token=null
	var output:Dictionary=packet.get("faces",{}) if packet is Dictionary else {}
	for id:String in _charge.rows.keys():
		if _ready.has(id) or _charge.rows[id].get("consumer",false):continue
		var faces:Variant=output.get(id)
		if faces is PackedVector3Array and not faces.is_empty() and faces.size()*12==int(_charge.rows[id].bytes):_ready[id]=faces
		else:_charge.erase(id)
	_update_profile()

func request(requests:Array,tree:SceneTree)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.collision_face_prefetch.request") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	poll()
	if tree==null or _draining!=null:return false
	var wanted:Dictionary={}
	for row:Dictionary in requests:
		if row.get("source") is Mesh and row.get("cpu") is Mesh and row.get("basis") is Basis:
			wanted[key(row.source,row.cpu,row.basis)]=true
	# Ready values no longer in the current lookahead cannot grow a cache behind
	# the stream cursor. A running batch retains all of its charged inputs.
	for id:String in _ready.keys():
		if not wanted.has(id):_ready.erase(id);_charge.erase(id)
	if _thread!=null:_update_profile();return false
	var snapshots:Array=[];var added:Array[String]=[]
	var capacity:=clampi(byte_limit,0,MAX_BYTES)
	for row:Dictionary in requests:
		if snapshots.size()>=clampi(item_limit,0,MAX_ITEMS) or _charge.rows.size()>=clampi(item_limit,0,MAX_ITEMS):break
		if not row.get("source") is Mesh or not row.get("cpu") is Mesh or not row.get("basis") is Basis:continue
		var id:=key(row.source,row.cpu,row.basis)
		if _charge.rows.has(id):continue
		var snapshot:=_snapshot(row)
		if snapshot.is_empty():continue
		var bytes_:int=snapshot.count*12
		if bytes_>capacity-_charge.bytes:continue
		snapshot.id=id;snapshots.append(snapshot);added.append(id)
		_charge.rows[id]={"source":row.source,"cpu":row.cpu,"basis":row.basis,"bytes":bytes_}
		_charge.bytes+=bytes_
	_update_profile()
	if snapshots.is_empty():return false
	_thread=Thread.new();_token=Drainer.CancelToken.new()
	# The callback alone is weak. A tree-owned drainer keeps the lease (including
	# source materials) alive until the worker's CPU packet is released on main.
	_token.set_meta("admission_release",_charge.release)
	_token.set_meta("admission_owner",_charge)
	_drainer=Drainer.for_tree(tree);_drainer.watch(_thread,_token)
	var task:Callable=_build.bind(snapshots,_token)
	var error:int=thread_starter.call(_thread,task) if thread_starter.is_valid() else _thread.start(task)
	if error!=OK:
		_drainer.forget(_thread);_thread=null;_token=null
		for id:String in added:_charge.erase(id)
		profile.start_failures+=1;_update_profile();return false
	profile.batches+=1
	return true

func take(source:Mesh,cpu:Mesh,basis:Basis)->PackedVector3Array:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.collision_face_prefetch.take") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	poll()
	var id:=key(source,cpu,basis)
	if not _ready.has(id):return PackedVector3Array()
	var lease:Dictionary=_charge.rows.get(id,{})
	if lease.get("source")!=source or lease.get("cpu")!=cpu or lease.get("basis")!=basis:return PackedVector3Array()
	var faces:PackedVector3Array=_ready[id]
	_ready.erase(id);lease.consumer=true;profile.hits+=1;_update_profile()
	return faces

func pending(source:Mesh,cpu:Mesh,basis:Basis)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.collision_face_prefetch.pending") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	poll()
	var id:=key(source,cpu,basis)
	# A batch already owns this exact extraction and its byte reservation.
	# Consumers wait for that bounded producer instead of launching a duplicate.
	return _thread!=null and _charge.rows.has(id) and not _ready.has(id) and not _charge.rows[id].get("consumer",false)

func release(source:Mesh,cpu:Mesh,basis:Basis)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.collision_face_prefetch.release") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var id:=key(source,cpu,basis)
	if _charge.rows.get(id,{}).get("consumer",false):_charge.erase(id)
	_update_profile()

func cancel()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.collision_face_prefetch.cancel") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if _thread==null and _ready.is_empty() and _charge.rows.is_empty():_update_profile();return
	_ready.clear()
	# Leaving covered loading cancels lookahead, not a terrain consumer already
	# slicing its borrowed output. Move that charge out of the worker lease so
	# asynchronous draining cannot release it before the consumer clears _faces.
	var consumers:=Lease.new()
	for id:String in _charge.rows.keys():
		var row:Dictionary=_charge.rows[id]
		if not row.get("consumer",false):continue
		consumers.rows[id]=row;consumers.bytes+=int(row.bytes)
		_charge.erase(id)
	if _thread!=null:
		_token.cancel();_drainer.abandon(_thread)
		_draining=_charge;profile.cancelled_batches+=1
		_thread=null;_token=null
	else:_charge.release()
	_charge=consumers;_leases=_charge.rows
	_update_profile()

func has_source_owners()->bool:
	return not _charge.rows.is_empty() or (_draining!=null and not _draining.rows.is_empty())

func release_sources(meshes:Dictionary)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.collision_face_prefetch.release_sources") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	poll()
	for lease:Lease in [_charge,_draining]:
		if lease==null:continue
		for row:Dictionary in lease.rows.values():
			if meshes.has(row.source.get_instance_id()) or meshes.has(row.cpu.get_instance_id()):
				if lease==_draining or _thread!=null or row.get("consumer",false):return false
	for id:String in _ready.keys():
		var row:Dictionary=_charge.rows[id]
		if meshes.has(row.source.get_instance_id()) or meshes.has(row.cpu.get_instance_id()):_ready.erase(id);_charge.erase(id)
	_update_profile()
	return true

static func _snapshot(row:Dictionary)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.collision_face_prefetch._snapshot") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var cpu:Mesh=row.cpu
	if not cpu is Cpu:return {}
	var basis:Basis=row.basis
	if not basis.is_finite():return {}
	var completed:PackedVector3Array=cpu._collision_faces
	if not completed.is_empty():
		if completed.size()%3!=0:return {}
		return {"count":completed.size(),"faces":completed,"basis":basis,"surfaces":[]}
	var surfaces:Array=cpu.surfaces.duplicate()
	var count:=0
	for slot in surfaces.size():
		var arrays:Variant=surfaces[slot]
		if not arrays is Array or arrays.size()!=Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:return {}
		# Isolate each channel slot too; PackedArray payload remains shared by
		# value/COW, never an Array container that main can replace under us.
		surfaces[slot]=arrays.duplicate()
		var indices:Variant=arrays[Mesh.ARRAY_INDEX]
		if indices!=null and not indices is PackedInt32Array:return {}
		count+=indices.size() if indices!=null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
		if count>MAX_BYTES/12:return {}
	if count==0 or count%3!=0:return {}
	return {"count":count,"faces":PackedVector3Array(),"basis":basis,"surfaces":surfaces}

static func _build(snapshots:Array,token:RefCounted)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.collision_face_prefetch._build") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var output:Dictionary={}
	for snapshot:Dictionary in snapshots:
		if token.is_cancelled():return {}
		var faces:PackedVector3Array=snapshot.faces
		if faces.is_empty():
			faces.resize(snapshot.count);var at:=0
			for arrays:Array in snapshot.surfaces:
				var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var indices:Variant=arrays[Mesh.ARRAY_INDEX]
				if indices!=null and not indices.is_empty():
					for index:int in indices:
						if index<0 or index>=vertices.size():return {}
						if at%4096==0 and token.is_cancelled():return {}
						faces[at]=vertices[index];at+=1
				else:
					for vertex:Vector3 in vertices:
						if at%4096==0 and token.is_cancelled():return {}
						faces[at]=vertex;at+=1
		elif snapshot.basis!=Basis.IDENTITY:faces=faces.duplicate()
		if snapshot.basis!=Basis.IDENTITY:
			for i in faces.size():
				if i%4096==0 and token.is_cancelled():return {}
				faces[i]=snapshot.basis*faces[i]
		output[snapshot.id]=faces
	return {"faces":output}
