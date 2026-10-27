extends RefCounted
## Opt-in, main-thread diagnostic. No scene objects, Resources or live demand
## dictionaries are retained. Events stop at a fixed capacity; counters keep
## showing how many changes and refreshes were omitted.
const MAX_CAPACITY:=32768
const MAX_SCOPE_IDS:=16
var capacity:int
var events:Array=[]
var source_counts:Dictionary={}
var pending_causes:Dictionary={}
var dropped_changes:=0
var dropped_refreshes:=0
var record_us:=0
var max_record_us:=0
var last_consumed_revision:=-1
var started_us:=0

func _init(requested_capacity:int=4096)->void:
	capacity=clampi(requested_capacity,1,MAX_CAPACITY)
	started_us=Time.get_ticks_usec()

static func _value(value:Variant)->Variant:
	if value is Dictionary:
		# Copy just scheduler scalars, never the mutable dictionary itself.
		var clip:Variant=value.get("clip")
		var priority:Variant=value.get("priority")
		var kind:Variant=value.get("kind")
		var group:Variant=value.get("group_id")
		var rank:Variant=value.get("rank_from_player")
		return [clip if clip is AABB else null,priority if priority is int or priority is float else null,
			kind.left(128) if kind is String else "",group.left(128) if group is String else "",rank if rank is bool else false]
	if value is String:return value.left(128)
	if value==null or value is bool or value is int or value is float or value is Vector3 or value is AABB:return value
	return null

func _charge(began:int)->void:
	var elapsed:=Time.get_ticks_usec()-began
	record_us+=elapsed;max_record_us=maxi(max_record_us,elapsed)

func change(kind:String,id:String,old_value:Variant,new_value:Variant,revision:int)->void:
	var began:=Time.get_ticks_usec()
	source_counts[kind]=int(source_counts.get(kind,0))+1
	pending_causes[kind]=int(pending_causes.get(kind,0))+1
	if events.size()>=capacity:dropped_changes+=1
	else:
		events.append({"type":"change","ticks_us":began,"at_us":began-started_us,"frame":Engine.get_process_frames(),"revision":revision,
			"source":kind,"id":id.left(128),"id_truncated":id.length()>128,"old_value":_value(old_value),"new_value":_value(new_value)})
	_charge(began)

func scope_change(kind:String,old_scope:Dictionary,new_scope:Dictionary,revision:int)->void:
	var previous_size:=events.size()
	change(kind,"",old_scope.size(),new_scope.size(),revision)
	if events.size()==previous_size:return
	var began:=Time.get_ticks_usec()
	var added:Array[String]=[];var removed:Array[String]=[];var added_count:=0;var removed_count:=0;var id_truncated:=false
	for key:Variant in new_scope:
		if old_scope.has(key) or not key is String:continue
		added_count+=1
		if key.length()>128:id_truncated=true
		if added.size()<MAX_SCOPE_IDS:added.append(key.left(128))
	for key:Variant in old_scope:
		if new_scope.has(key) or not key is String:continue
		removed_count+=1
		if key.length()>128:id_truncated=true
		if removed.size()<MAX_SCOPE_IDS:removed.append(key.left(128))
	var event:Dictionary=events.back()
	event.scope_added=added;event.scope_removed=removed
	event.scope_added_count=added_count;event.scope_removed_count=removed_count
	event.scope_truncated=id_truncated or added_count>added.size() or removed_count>removed.size()
	_charge(began)

func begin_refresh(revision:int,previous_revision:int,priority:Vector3,anchor:Variant,began:int,demands:int,scope_count:int)->Dictionary:
	# Swap, rather than clear at end: a reentrant revision belongs to the next
	# refresh even if it is recorded while this refresh is still executing.
	var record_began:=Time.get_ticks_usec()
	var causes:Dictionary=pending_causes;pending_causes={}
	var ticket:Dictionary={"begin_us":began,"at_us":began-started_us,"frame":Engine.get_process_frames(),"revision":revision,"previous_revision":previous_revision,
		"last_consumed_revision":last_consumed_revision,"initial":previous_revision<0,"priority":priority,"anchor":_value(anchor),
		"demands":demands,"scope_count":scope_count,"causes":causes}
	_charge(record_began);return ticket

func end_refresh(ticket:Dictionary,revision_after:int,pending_count:int,demanded_count:int,profile:Dictionary)->void:
	var began:=Time.get_ticks_usec()
	last_consumed_revision=int(ticket.revision)
	if events.size()>=capacity:dropped_refreshes+=1
	else:
		ticket.type="refresh";ticket.end_us=began;ticket.elapsed_us=maxi(0,began-int(ticket.begin_us));ticket.revision_after=revision_after
		ticket.pending=pending_count;ticket.demanded=demanded_count
		# These are cumulative work counters. Difference successive records to
		# obtain a window, never treat them as the duration of a single method.
		var work:Dictionary={}
		for key:String in ["demand_input_rows","demand_membership_hits","demand_membership_misses","demand_kind_tests","demand_distance_evaluations","demand_scores_reused","spatial_script_rows","spatial_candidate_tests","demand_refreshes"]:
			work[key]=int(profile.get(key,0))
		ticket.work=work;events.append(ticket)
	_charge(began)

func snapshot()->Dictionary:
	return {"events":events.duplicate(true),"capacity":capacity,"started_us":started_us,"source_counts":source_counts.duplicate(),
		"pending_causes":pending_causes.duplicate(),"dropped_changes":dropped_changes,"dropped_refreshes":dropped_refreshes,
		"record_us":record_us,"max_record_us":max_record_us,
		"contract":"Opt-in bounded diagnostic. Timestamps are monotonic; initial means the queue had no prior candidates revision, not the first event in this session. Causes before enabling are unknown. Events may nest and include recorder overhead. Source counts include dropped events. record_us covers recorder methods, not runner tick checks or final snapshot copying."}
