extends RefCounted
## Per-world-session peer stream. Temporary hiding never retires a generation.
## A full snapshot replaces the visible set; older HTTP/socket frames are inert.
const MAX_REVISION:=9007199254740991
var revision:=0
var peers:Dictionary={}

func clear()->void:
	revision=0;peers.clear()

static func _integer(value:Variant,minimum:int=0)->bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)==floorf(float(value)) and value>=minimum and value<=MAX_REVISION

static func _actor_ok(actor:Variant,map_ref:String,self_id:String)->bool:
	if not actor is Dictionary:return false
	var id:=str(actor.get("id",""))
	if id.is_empty() or id==self_id or not _integer(actor.get("generation",0),1) or not _integer(actor.get("sequence",0)):return false
	var location:Variant=actor.get("location",{})
	if not location is Dictionary or location.get("map_ref","")!=map_ref:return false
	var point:Variant=location.get("position_m",{})
	if not point is Dictionary:return false
	for axis:String in ["x","y","z"]:
		var value:Variant=point.get(axis,0.)
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)):return false
	return true

func apply(update:Dictionary,map_ref:String,self_id:String)->Dictionary:
	if not _integer(update.get("revision",0),1):return {"ok":false,"error":"invalid_visibility_revision"}
	var incoming:=int(update.revision)
	if incoming<=revision:return {"ok":true,"ignored":true}
	var full:Variant=update.get("full_snapshot",false)
	if not full is bool:return {"ok":false,"error":"invalid_visibility_snapshot"}
	if not full and (revision==0 or incoming!=revision+1):return {"ok":true,"gap":true}
	var rows:Variant=update.get("actors",[]);var hidden:Variant=update.get("hidden",[])
	if not rows is Array or not hidden is Array or rows.size()>2048 or hidden.size()>2048:return {"ok":false,"error":"invalid_visibility_size"}
	var seen:Dictionary={}
	for actor:Variant in rows:
		if not _actor_ok(actor,map_ref,self_id) or seen.has(str(actor.id)):return {"ok":false,"error":"invalid_visibility_actor"}
		seen[str(actor.id)]=true
	for actor:Variant in hidden:
		if not actor is Dictionary or str(actor.get("id","")).is_empty() or str(actor.id)==self_id or not _integer(actor.get("generation",0),1):return {"ok":false,"error":"invalid_visibility_hide"}
	# Validate the entire frame before mutating the projection.
	var next:Dictionary={} if full else peers.duplicate()
	if not full:
		for actor:Dictionary in hidden:
			var id:=str(actor.id)
			if next.has(id) and int(next[id].generation)==int(actor.generation):next.erase(id)
	for actor:Dictionary in rows:next[str(actor.id)]=actor.duplicate(true)
	if next.size()>2048:return {"ok":false,"error":"visibility_capacity"}
	var removed:Array=[]
	for id:String in peers:
		if not next.has(id) or int(next[id].generation)!=int(peers[id].generation):removed.append(id)
	peers=next;revision=incoming
	return {"ok":true,"removed":removed,"actors":rows}
