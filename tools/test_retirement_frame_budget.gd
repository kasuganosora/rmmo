extends "res://tools/test_stream_index_retire.gd"
const Stream=preload("res://scripts/world3d/world_stream.gd")
func next_frame()->void:
	var previous:=Engine.get_process_frames()
	while Engine.get_process_frames()==previous:await process_frame
func run()->void:
	var library:Array=[]
	for id:String in ["first","second","third"]:library.append(spec(id,Vector2i(100,100),Vector2i(100,100),{"kind":"asset"}))
	var data:=Index.build(library);var map:=Node3D.new();root.add_child(map)
	for key:String in data:map.set_meta(key,data[key])
	map.set_meta("stream_library",library);map.set_meta("stream_chunk",Vector2i.ZERO)
	check(Stream.retire_specs(map,["first"],false,null,"ordinary_retirement").ok,"ordinary owner completes the real source/index transaction")
	# A declared 3 ms indivisible cost, with no sleep or busy loop.
	Stream.charge_retirement_work(map,"ordinary_retirement",Time.get_ticks_usec()-3000)
	var before:=data.duplicate(true)
	var denied:=Stream.retire_specs(map,["second"],true,null,"native_retirement")
	check(not denied.ok and denied.error=="retirement_budget" and data==before,"overrun defers the other owner without partially retiring its source")
	var ledger:RefCounted=map.get_meta("retirement_frame_budget")
	check(ledger.snapshot().current_spent_us>=3000 and ledger.snapshot().lanes.ordinary_retirement.max_call_us>=3000,"cleanup and actual overshoot remain visible in the same map-local ledger")
	await next_frame()
	var earlier:=Stream.retire_specs(map,["third"],false,null,"ordinary_retirement")
	check(not earlier.ok and earlier.error=="retirement_budget","the previous earlier scene callback yields to the starved native owner")
	check(Stream.retire_specs(map,["second"],true,null,"native_retirement").ok,"protected native turn still runs the real complete-unit validation and commit")
	Stream.charge_retirement_work(map,"native_retirement",Time.get_ticks_usec()-3000)
	await next_frame()
	check(Stream.retire_specs(map,["third"],false,null,"ordinary_retirement").ok,"ordinary owner receives its protected next turn without starvation")
	check(library.is_empty() and map.get_meta("stream_by_id").is_empty(),"both owners eventually remove every requested original source")
	var other:=Node3D.new();root.add_child(other)
	check(Stream._retirement_budget(other).request(Engine.get_process_frames(),"native_retirement",2000)==2000,"a second map has independent retirement admission and waiting lanes")
	other.free();map.free();data.clear();library.clear()
	check(ledger.snapshot().current_limit_us==2000 and not preload("res://scripts/world3d/frame_work_budget.gd").enabled,"dedicated retirement scheduling leaves the separate global loading ledger disabled")
	print("RETIREMENT_FRAME_BUDGET checks=",checks," failures=",failures);quit(1 if failures else 0)
