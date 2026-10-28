extends Node
## One speculative CPU-only native target. No scene, GLTF import or authority
## activation is performed while the source map remains playable.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Snapshot=preload("res://scripts/world3d/document_source_snapshot.gd")
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Plan=preload("res://scripts/world3d/entry_plan.gd")
const PackagePolicy=preload("res://scripts/world3d/runtime_package_policy.gd")
const LEASE_BYTES=512*1024*1024
const MAX_HEADER_BYTES=4*1024*1024
const MAX_INDEX_BYTES=8*1024*1024
const MAX_RECORDS=4096
static var enabled:=true
class Packet extends RefCounted:
	var snapshot:RefCounted
	var restored:Dictionary={}
	var selected:Array=[]
	var path:=""
	var cell:=Vector2i.ZERO
	var scene_plan:Dictionary={}
var profile:Dictionary={"started":0,"ready":0,"hits":0,"cancelled":0,"misses":0}
var _thread:Thread
var _token:RefCounted
var _ledger:RefCounted
var _drainer:Node
var _lease:=""
var _target:=""
var _cell:=Vector2i.ZERO
var _packet:Packet
var _touched:=0
var _failed_until:=0
func request(path:String,origin:Vector3,ledger:RefCounted)->bool:
	if not enabled or not origin.is_finite() or not Paths.allowed(path) or path.get_extension().to_lower()!="gltf":return false
	var cell:Vector2i=Plan.create(origin).cell
	if path==_target and cell==_cell:
		_touched=Time.get_ticks_msec();return _packet!=null or _thread!=null
	cancel()
	if _thread!=null or ledger==null or Time.get_ticks_msec()<_failed_until:return false
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return false
	var length:=file.get_length();file.close()
	if length<=0 or length>MAX_HEADER_BYTES:return false
	_token=Drainer.CancelToken.new();_lease="cross_map_cpu:%d"%get_instance_id()
	if not ledger.reserve_background(_lease,LEASE_BYTES,_token.cancel):return false
	_ledger=ledger;_target=path;_cell=cell;_touched=Time.get_ticks_msec()
	_token.set_meta("admission_owner",ledger);_token.set_meta("admission_release",ledger.release.bind(_lease))
	_thread=Thread.new();_drainer=Drainer.for_tree(get_tree());_drainer.watch(_thread,_token)
	var task:=prepare.bind(path,origin,Paths.external_root(),_token,LEASE_BYTES)
	if _thread.start(task)!=OK:_drainer.forget(_thread);_thread=null;_release();return false
	profile.started+=1;set_process(true);return true
static func _envelope(extra:Dictionary,header_bytes:int,path:String,root:String)->int:
	# Bound decoded Variant copies per INSTANCE, not compressed rmres length.
	# Unique IO buffers and the directory/selection workspace are separate terms.
	var total:=header_bytes*64+MAX_INDEX_BYTES*8;var seen:Dictionary={}
	for row:Dictionary in extra.get("rmmo_records",[]):
		var ref:Dictionary=row.get("rmmo_ref",{});var key:String=str(ref.get("uri",""))
		if not seen.has(key):
			var location:=Store._location(key,ref.get("sha256"),path,root)
			if location.is_empty():return LEASE_BYTES+1
			var file:=FileAccess.open(location,FileAccess.READ)
			if file==null or file.get_length()!=int(ref.get("length",0)):return LEASE_BYTES+1
			var header:=file.get_buffer(16);file.close()
			if header.size()!=16 or header.slice(0,8).get_string_from_ascii()!=Store.MAGIC:return LEASE_BYTES+1
			var raw:=header.decode_u64(8)
			if raw<=0 or raw>Store.MAX_RAW_BYTES:return LEASE_BYTES+1
			seen[key]=raw;total+=int(ref.length)
		total+=int(seen[key])*16+65536
	return total
static func prepare(path:String,origin:Vector3,root:String,token:RefCounted,budget:int)->Dictionary:
	if token.is_cancelled() or not Paths.allowed(path,root):return {}
	var source:RefCounted=Snapshot.read_file(path,MAX_HEADER_BYTES,MAX_HEADER_BYTES)
	if not source.error.is_empty() or token.is_cancelled():return {}
	var native:int=Cursor.native_root(source._data)
	if native<0:return {} # Raw maps retain the confirmed-transfer loader route.
	var extra:Dictionary=source._data.nodes[native].extras
	if extra.rmmo_records.size()>MAX_RECORDS:return {}
	var directory:Dictionary=Index.read_for_loading(path,root,source._signature,MAX_HEADER_BYTES,MAX_INDEX_BYTES,1,PackagePolicy.trusted(),null,true)
	if token.is_cancelled():return {}
	if not directory.ok:
		if _envelope(extra,source._bytes.size(),path,root)>budget:return {}
		var whole:Dictionary=Cursor.hydrate_references(extra,path,root,1,PackagePolicy.trusted())
		if not whole.get("ok",false) or token.is_cancelled():return {}
		var built:Dictionary=Index.build_for_loading(path,root,whole.extras.rmmo_records,source._signature,1,MAX_HEADER_BYTES,PackagePolicy.trusted(),whole.get("definition_sizes",{}),{},null,true)
		if not built.ok or token.is_cancelled():return {}
		whole.clear();directory=built
	if not directory.ok or token.is_cancelled():return {}
	var selection:Dictionary=Index.select(directory.index,[Plan.create(origin).core_clip])
	if not selection.ok or _envelope(selection.extras,source._bytes.size(),path,root)>budget or token.is_cancelled():return {}
	var restored:Dictionary=Cursor.hydrate_references(selection.extras,path,root,1,PackagePolicy.trusted())
	if not restored.get("ok",false) or token.is_cancelled() or not source.matches_disk():return {}
	var packet:=Packet.new();packet.snapshot=source;packet.restored=restored;packet.selected=selection.record_indices.duplicate();packet.path=path;packet.cell=Plan.create(origin).cell
	packet.scene_plan=preload("res://scripts/world3d/target_scene_prefetch.gd").plan(restored.extras.rmmo_records,root,path,source._signature,restored.dependencies)
	return {"packet":packet}
func _process(_delta:float)->void:
	poll()
	if _packet!=null and Time.get_ticks_msec()-_touched>10000:cancel()
func poll()->void:
	if _token!=null and _token.is_cancelled():_packet=null
	if _thread==null or _thread.is_alive():
		if _thread==null and _packet==null:_release();set_process(false)
		return
	var result:Dictionary=_thread.wait_to_finish();_drainer.forget(_thread);_thread=null
	if _ledger!=null:_ledger.park(_lease)
	if not _token.is_cancelled() and result.has("packet"):
		_packet=result.packet;profile.ready+=1
	else:
		result.clear();profile.misses+=1;_failed_until=Time.get_ticks_msec()+2000;_release()
func take(path:String,origin:Vector3)->Packet:
	poll()
	if _packet!=null and _target==path and _cell==Plan.create(origin).cell:
		var result:Packet=_packet;_packet=null;profile.hits+=1;_release();return result
	cancel();return null
func cancel()->void:
	if _token!=null:_token.cancel()
	_packet=null
	if _thread==null:_release()
	else:profile.cancelled+=1
func drain()->void:
	cancel()
	while _thread!=null:
		poll()
		if _thread!=null:await get_tree().process_frame
func _release()->void:
	if _token!=null:
		if _token.has_meta("admission_release"):_token.remove_meta("admission_release")
		if _token.has_meta("admission_owner"):_token.remove_meta("admission_owner")
	if _ledger!=null:_ledger.release(_lease)
	_ledger=null;_token=null;_target="";_lease=""
func _exit_tree()->void:
	_packet=null
	if _thread!=null:
		_token.cancel()
		if is_instance_valid(_drainer):_drainer.abandon(_thread)
		else:Drainer.drain_shutdown(_thread,_token)
		_thread=null;_ledger=null;_token=null
	else:_release()
