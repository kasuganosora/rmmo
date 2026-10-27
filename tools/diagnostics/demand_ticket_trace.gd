extends RefCounted
## Optional main-thread diagnostic; stores scalar summaries, never live items.
## The UUID sequence compares input rows only, not the identity of their owners.
const MAX_EVENTS:=16384
const MAX_TRACKED_TICKETS:=128
const MAX_MEMBERS:=512
const MAX_ID_LENGTH:=128
var capacity:int
var events:Array=[]
var previous:Dictionary={}
var dropped:=0
var untracked:=0
var evicted:=0

func _init(requested:int=1024)->void:
	capacity=clampi(requested,1,MAX_EVENTS)

func begin_ticket(id:String,origin:Vector3,priority:int,revision:int,cache_hit:bool,input_rows:int,support_visits:int)->Variant:
	if events.size()>=capacity:
		dropped+=1
		return null
	var can_track:bool=id.length()<=MAX_ID_LENGTH
	# The return route visits many short-lived building approach IDs. Retain the
	# most recently observed bounded set; a later reappearance is unknown.
	if can_track and not previous.has(id) and previous.size()>=MAX_TRACKED_TICKETS:
		previous.erase(previous.keys()[0]);evicted+=1
	if not can_track:untracked+=1
	return {"id":id.left(MAX_ID_LENGTH),"id_truncated":id.length()>MAX_ID_LENGTH,"track":can_track,"revision":revision,"frame":Engine.get_process_frames(),
		"origin":origin,"priority":priority,"membership_cache_hit":cache_hit,"input_rows":input_rows,"members":[],"complete_members":can_track,
		"kind_excluded":0,"published":0,"new_uuid":0,"duplicate_uuid":0,"winner_changes":0,"support_start":support_visits}

func member(ticket:Dictionary,record:Variant)->void:
	if not ticket.track or not ticket.complete_members:return
	if not record is Dictionary or not record.get("uuid") is String:
		ticket.complete_members=false;ticket.members.clear();return
	var uuid:String=record.uuid
	if uuid.length()>MAX_ID_LENGTH or ticket.members.size()>=MAX_MEMBERS:
		ticket.complete_members=false;ticket.members.clear();return
	ticket.members.append(uuid)

func end_ticket(ticket:Dictionary,support_visits:int)->void:
	var id:String=ticket.id
	var old:Variant=previous.get(id) if ticket.track else null
	ticket.membership_uuid_sequence_changed=null
	ticket.origin_changed=null
	ticket.priority_changed=null
	if old!=null:
		ticket.origin_changed=old.origin!=ticket.origin
		ticket.priority_changed=old.priority!=ticket.priority
		if old.complete_members and ticket.complete_members:ticket.membership_uuid_sequence_changed=old.members!=ticket.members
	if ticket.track:
		previous.erase(id) # Reinsert at the end for bounded LRU ordering.
		previous[id]={"origin":ticket.origin,"priority":ticket.priority,"complete_members":ticket.complete_members,"members":ticket.members}
	ticket.support_visits=support_visits-int(ticket.support_start)
	ticket.erase("support_start");ticket.erase("members");ticket.erase("track")
	events.append(ticket)

func snapshot()->Dictionary:
	return {"events":events.duplicate(true),"capacity":capacity,"dropped":dropped,"untracked":untracked,"evicted":evicted,"tracked_tickets":previous.size(),
		"limits":{"events":MAX_EVENTS,"tracked_tickets":MAX_TRACKED_TICKETS,"members_per_ticket":MAX_MEMBERS,"id_characters":MAX_ID_LENGTH},
		"contract":"Diagnostic only. At most 16384 scalar event records and 128 recent ticket snapshots of 512 UUIDs of at most 128 characters each are retained; one current ticket and the returned snapshot are additional. These bounds do not measure RSS or container overhead. Membership is the exact ordered input UUID sequence when complete; it does not establish owner identity. Changes compare the last retained observation for that ticket, which may precede the preceding refresh. Null change means no prior complete tracked comparison, including eviction. Input rows partition into kind_excluded, published, new_uuid and duplicate_uuid; duplicate includes UUIDs introduced by prior support closure. winner_changes counts replacement of existing winners only; support winners are separate. Timings with this diagnostic enabled are contaminated."}
