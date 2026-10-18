extends RefCounted
## Schema-only preparation. It never authorizes pins, geometry, dependencies,
## navigation or a commit. Those checks still run in the final transaction.
const Index=preload("res://scripts/world3d/stream_index.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
var source:Array=[]
var snapshots:Array=[]
var seen:Dictionary={}
var namespace_sizes:Dictionary={}
var cursor:=0
var error:=""
var complete:=false
var profile:Dictionary={"rows":0,"slices":0,"max_slice_us":0,"elapsed_us":0,"verifications":0,"retired":0}
func begin(library:Array)->void:
	source=library.duplicate()
static func _snapshot(value:Dictionary)->Dictionary:
	# _valid_append_spec reads nested building.id and ground size[1]. Copy
	# those owners; all other nested author/derived arrays remain borrowed.
	# In-place edits of a validated field therefore fail native equality,
	# without copying geometry/material graphs irrelevant to this schema.
	var result:Dictionary=value.duplicate()
	for field:String in ["extras","ground_batch_record"]:
		if not value.has(field):continue
		var record:Dictionary=value[field].duplicate()
		if record.has("building"):record.building=record.building.duplicate()
		if field=="ground_batch_record" and record.get("kind")=="box" and record.get("surface_id")=="ground" and record.has("size"):record.size=record.size.duplicate()
		result[field]=record
	return result
func advance(budget_usec:int)->bool:
	if complete or not error.is_empty():return true
	var started:=Time.get_ticks_usec();var advanced:=false
	while cursor<source.size() and error.is_empty() and (not advanced or Time.get_ticks_usec()-started<budget_usec):
		advanced=true;var value:Variant=source[cursor]
		if not Index._valid_append_spec(value):error="library/index identity mismatch";break
		var id:String=value.uuid
		if seen.has(id):error="library/index identity mismatch";break
		seen[id]=true;var prefix:=id.get_slice("__",0)
		namespace_sizes[prefix]=int(namespace_sizes.get(prefix,0))+1
		snapshots.append(_snapshot(value));cursor+=1;profile.rows+=1
	complete=cursor==source.size() and error.is_empty()
	var elapsed:=Time.get_ticks_usec()-started
	profile.slices+=1;profile.elapsed_us+=elapsed;profile.max_slice_us=maxi(profile.max_slice_us,elapsed)
	return complete or not error.is_empty()
func valid_for(library:Array,by_id:Dictionary)->bool:
	profile.verifications+=1
	# Godot native equality retains exact Variant types, including nested
	# String/StringName distinctions. No revision or hash substitutes for it.
	if not complete or not error.is_empty() or library.size()!=source.size() or library.size()!=by_id.size():return false
	return preload("res://scripts/world3d/spec_snapshot_validation.gd").matches(library,snapshots,source,by_id)
func retired(ids:Array)->bool:
	# Ordinary and native commits may remove sources while this cursor is
	# still preparing. Preserve the validated survivor prefix rather than
	# restarting the entire resident scan after each small ordinary batch.
	if not error.is_empty():return false
	var requested:Dictionary={}
	for id:String in ids:requested[id]=true
	var removed:Array=[];var write:=0;var validated_write:=0;var validated:=cursor
	for read:int in source.size():
		var value:Variant=source[read]
		if not value is Dictionary or not value.get("uuid") is String:
			Retirement.defer_private_array(removed);return false
		var id:String=value.uuid
		if requested.has(id):
			removed.append(value)
			if read<validated:
				# Use the captured identity; an already removed source could have
				# been renamed after preparation. Survivors are checked afresh.
				var old_id:String=snapshots[read].uuid
				removed.append(snapshots[read]);seen.erase(old_id)
				var prefix:=old_id.get_slice("__",0);var count:=int(namespace_sizes.get(prefix,0))-1
				if count<=0:namespace_sizes.erase(prefix)
				else:namespace_sizes[prefix]=count
			profile.retired+=1;continue
		source[write]=value;write+=1
		if read<validated:snapshots[validated_write]=snapshots[read];validated_write+=1
	source.resize(write);snapshots.resize(validated_write);cursor=validated_write
	complete=cursor==source.size()
	Retirement.defer_private_array(removed)
	return true
func _notification(what:int)->void:
	if what==NOTIFICATION_PREDELETE:
		Retirement.defer_private_array(source)
		Retirement.defer_private_array(snapshots)
