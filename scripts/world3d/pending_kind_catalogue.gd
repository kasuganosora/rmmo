extends RefCounted
## Scheduling-only index. Large and ordinary owners keep separate insertion
## order, matching the spatial query's large-first, then pending traversal.
const KINDS:Array[String]=["building","road","structure","terrain"]
var large:Dictionary={"building":{},"road":{},"structure":{},"terrain":{}}
var ordinary:Dictionary={"building":{},"road":{},"structure":{},"terrain":{}}
var owners:Dictionary={}
var building_count:=-1
func add(item:Dictionary,is_large:bool,learned:Dictionary)->void:
	var uuid:String=item.record.uuid
	if owners.has(uuid):remove(owners[uuid][0])
	var mask:=0
	if str(item.get("group_id","")).begins_with("building:") or learned.has(uuid):mask|=1
	var reason:Variant=item.get("reference_entry",{}).get("reason","")
	if reason=="native_road":mask|=2
	if reason in ["native_fortification","native_bridge"]:mask|=4
	if reason=="terrain_context_global":mask|=8
	owners[uuid]=[item,mask,is_large]
	var buckets:Dictionary=large if is_large else ordinary
	for at:int in KINDS.size():
		if mask&(1<<at):buckets[KINDS[at]][uuid]=item
func remove(item:Dictionary)->void:
	var uuid:String=item.record.uuid;var owner:Array=owners.get(uuid,[])
	if owner.is_empty() or not is_same(owner[0],item):return
	var buckets:Dictionary=large if owner[2] else ordinary
	for at:int in KINDS.size():
		if int(owner[1])&(1<<at):buckets[KINDS[at]].erase(uuid)
	owners.erase(uuid)
func items(kind:String)->Array:
	var ordered:Dictionary=large[kind].duplicate()
	ordered.merge(ordinary[kind],true)
	return ordered.values()
