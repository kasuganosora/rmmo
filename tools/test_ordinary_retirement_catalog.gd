extends "res://tools/test_sliced_native_retirement.gd"
func run()->void:
	Stream.resident_retirement_catalog_enabled=true
	var f:=setup();f.map.set_meta("stream_chunk",Vector2i(-100,-100))
	var ids:Array=["keep3","keep100","keep2000","keep2399"]
	var timings:Array=[]
	for cached:bool in [false,true,true,false]:
		var began:=Time.get_ticks_usec()
		for repeat:int in 30:
			var plan:=Index._retire_plan(f.data,f.library,ids,cached)
			check(plan.ok and plan.removed_specs.size()==4,"ordinary plan selects only requested sources") if repeat==0 else null
		timings.append({"catalog":cached,"us":Time.get_ticks_usec()-began})
	var original:Array=f.library.duplicate();var expected:=original.duplicate();var control:=Index.build(expected)
	check(Index.retire(control,expected,ids).ok,"full reference retirement succeeds")
	var result:=Stream.retire_specs(f.map,ids,false,f.nav,"ordinary_retirement")
	check(result.ok and f.library==expected and f.nav._specs==expected,"runtime index/navigation preserve all ordered survivors")
	check(same_contents(f.map.get_meta("stream_append_state"),control.stream_append_state),"scalar catalogue matches full control")
	await process_frame
	var item:Dictionary=f.map.get_meta("stream_by_id").keep0
	item.extras.event={}
	check(not Stream.retire_specs(f.map,["keep0"],false,f.nav,"ordinary_retirement").ok and f.nav._spec_ids.has("keep0"),"new gameplay owner rejects before navigation changes")
	item.extras.erase("event")
	check(not Index._retire_plan(f.data,f.library,["guild__part0"],true).ok,"ordinary lane cannot remove a building member")
	var parts:Array=[spec("prop__a"),spec("prop__b")];var data:=Index.build(parts)
	check(not Index._retire_plan(data,parts,["prop__a"],true).ok,"partial imported parts is rejected")
	check(not Index._retire_plan(data,parts,["prop__a","prop__a"],true).ok,"duplicate identities are rejected")
	check(Index._retire_plan(data,parts,["prop__b","prop__a"],true).ok,"whole ordinary parts is eligible")
	print("ORDINARY_RETIREMENT_CATALOG ",JSON.stringify(timings))
	f.map.free();f={};drain()
	print("ORDINARY_RETIREMENT_CATALOG failures=",failures);quit(1 if failures else 0)
