extends RefCounted
## One load's already hydrated, private records, transferred once to deferred
## workers. No process cache, deep copies, file identities or decoded geometry.
const MAX_BYTES:=256*1024*1024
var index:Dictionary={}
var records:Dictionary={}
var reserved_bytes:=0
var transferred:=0
static func create(source:Dictionary,full:Array,deferred:Array,sizes:Dictionary,limit:int=MAX_BYTES)->RefCounted:
	var pool:=new();pool.index=source
	for entry:Dictionary in deferred:
		var compact:Dictionary=entry.compact_record
		var raw:=int(sizes.get(compact.rmmo_ref.sha256,0))
		if raw<=0:continue
		var cost:=raw*8+65536
		if pool.reserved_bytes+cost>mini(limit,MAX_BYTES):continue
		pool.records[compact.uuid]=full[entry.record_index]
		pool.reserved_bytes+=cost
	return pool
func take(source:Dictionary,entries:Array)->Dictionary:
	if not is_same(index,source):return {}
	var result:Dictionary={}
	for entry:Dictionary in entries:
		var uuid:String=entry.compact_record.uuid
		if records.has(uuid):result[uuid]=records[uuid];records.erase(uuid);transferred+=1
	return result
func retire()->void:
	# Cancellation must not drop thousands of private definitions in one frame.
	var values:=records.values();records.clear();index={}
	preload("res://scripts/world3d/resource_retirement.gd").defer_private_array(values)
