extends "res://tools/test_parallel_retirement_schema.gd"
const Preparation=preload("res://scripts/world3d/retirement_schema_preparation.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
func prepared(f:Dictionary)->RefCounted:
	var p:RefCounted=Preparation.new();p.begin(f.library)
	var turns:=0
	while not p.advance(1500):turns+=1
	check(turns>1 and p.complete and p.error.is_empty(),"full resident schema is prepared across bounded slices")
	check(p.valid_for(f.library,f.data.stream_by_id),"fresh native equality and exact dictionary identities authorize the current library")
	return p
func drain()->void:
	var service:Node=root.get_node(Retirement.NODE_NAME);service.set_process(false)
	while not service.pending.is_empty():
		if service._advance(service.pending[0],1000):service._finish_front()
func run()->void:
	var f:=fixture();var p:RefCounted=prepared(f)
	var started:=Time.get_ticks_usec();var accepted:bool=p.valid_for(f.library,f.data.stream_by_id);var elapsed:=Time.get_ticks_usec()-started
	check(accepted,"reusable proof performs fresh verification each time")
	print("RETIREMENT_PREPARED_VERIFY us=",elapsed," profile=",p.profile)
	var original:Dictionary=f.library[-1].extras
	f.library[-1].extras=17;check(not p.valid_for(f.library,f.data.stream_by_id),"late surviving source corruption invalidates the proof");f.library[-1].extras=original
	f.library[0].ground_batch_record.building.id=17;check(not p.valid_for(f.library,f.data.stream_by_id),"nested mutation behind the completed cursor invalidates the proof");f.library[0].ground_batch_record.building.id="group0"
	check(p.valid_for(f.library,f.data.stream_by_id),"restoring exact relevant values permits reuse")
	var first:Dictionary=f.library[0];f.library[0]=first.duplicate();check(not p.valid_for(f.library,f.data.stream_by_id),"equal-value replacement still fails exact identity");f.library[0]=first
	f.data.stream_by_id[first.uuid]=first.duplicate();check(not p.valid_for(f.library,f.data.stream_by_id),"by-id alias replacement still fails exact identity");f.data.stream_by_id[first.uuid]=first
	var result:Dictionary=Index.retire_owned(f.data,f.library,f.ids);check(result.ok,"complete authoritative retirement succeeds")
	p.retired(f.ids);check(p.valid_for(f.library,f.data.stream_by_id) and p.source.size()==2400 and p.seen.size()==2400,"committed removal compacts only corresponding snapshot owners and keeps survivor proof")
	p=null;f={};first={};original={};result={};drain()
	f=fixture();p=Preparation.new();p.begin(f.library);p.advance(1)
	check(not p.complete and not p.valid_for(f.library,f.data.stream_by_id),"partial proof never authorizes a transaction")
	f.library[0].extras=17
	while not p.advance(1000):pass
	check(not p.valid_for(f.library,f.data.stream_by_id),"mutation behind a yielded cursor is detected before commit")
	p=null;f={};drain()
	for removal:Array in [["guild__part0"],["keep2399"],["guild__part0","keep2399"]]:
		f=fixture();p=Preparation.new();p.begin(f.library);p.advance(1)
		check(p.cursor>0 and p.cursor<4600,"fixture cursor leaves unvalidated suffix")
		var surviving:Array=[]
		for row:Dictionary in f.library:
			if row.uuid not in removal:surviving.append(row)
		f.library=surviving;f.data=Index.build(surviving)
		check(p.retired(removal),"committed prefix/suffix removals preserve partial ownership")
		while not p.advance(1000):pass
		check(p.valid_for(f.library,f.data.stream_by_id) and p.seen.size()==surviving.size(),"partial survivor proof completes with exact identities and counts")
		check(p.profile.rows<=4600,"small committed removal does not restart validated source work")
		p=null;f={};drain()
	print("SLICED_RETIREMENT_PROOF checks=",checks," failures=",failures);quit(1 if failures else 0)
