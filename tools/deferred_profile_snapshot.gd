extends RefCounted
## Measurement-only observer: history is copied once, outside counters stay
## scalar. Retain the complete profile once after timing, not every 500 ms.
var stages:Array=[]
var last_at_us:Dictionary={}
var copied_stage_rows:=0
var captures:=0

func capture(profile:Dictionary,owner_id:int)->Dictionary:
	var counters:Dictionary={}
	for key:Variant in profile:
		var value:Variant=profile[key]
		if value is Array or value is Dictionary:continue
		counters[key]=value
	# This small live ledger is useful at each queue observation; all other
	# detailed aggregate tables remain available in the final profile snapshot.
	if profile.get("main_thread_budgets") is Dictionary:counters.main_thread_budgets=profile.main_thread_budgets.duplicate(true)
	var ring:Array=profile.get("stage_ring",[])
	var last:int=last_at_us.get(owner_id,-1)
	var first:int=ring.size()
	while first>0 and int(ring[first-1].at_us)>last:first-=1
	for i:int in range(first,ring.size()):
		var row:Dictionary=ring[i].duplicate(true)
		row.observed_queue_id=owner_id;stages.append(row);copied_stage_rows+=1
	if not ring.is_empty():last_at_us[owner_id]=maxi(last,int(ring.back().at_us))
	captures+=1
	return counters
