extends "res://tools/test_owned_retirement_delta.gd"
func run()->void:
	var original:=world()
	var door:=spec("house2_door",Vector2i(6,1),Vector2i(6,1),{"building":{"id":"house2"}},{"building":{"id":"house2"},"fixture":{"id":"entry","kind":"door","open":0.}})
	original.append(door)
	for ids:Array in [["house1_part2","house1_part0","house1_part1"],["house0_part0","house0_part1","house0_part2","ground0"],["house2_part0","house2_part1","house2_part2","house2_door"],["road"],[],["ground0"],["house1_part0"]]:
		var old_library:=original.duplicate(true);var new_library:=original.duplicate(true)
		var old_data:=Index.build(old_library);var new_data:=Index.build(new_library)
		Index.reuse_owned_retirement_plan_enabled=false;var before:=Index.retire_owned(old_data,old_library,ids)
		Index.reuse_owned_retirement_plan_enabled=true;var after:=Index.retire_owned(new_data,new_library,ids)
		check(before==after and same_contents(old_data,new_data) and old_data.stream_append_state==new_data.stream_append_state and old_library==new_library,"same complete validation and commit with or without plan reuse: "+str(ids))
		if after.ok:equivalent(new_data,new_library,"reused complete plan")
	var library:=original.duplicate(true);var data:=Index.build(library);var frozen:=data.duplicate(true)
	var checked:=Index.validate_owned_retire(data,library,["road"])
	check(checked=={"ok":true,"error":"","removed":1} and data==frozen,"public preflight exposes no reusable authorization or owning resource arrays")
	for field:String in ["mesh","extras"]:
		library=original.duplicate(true);data=Index.build(library)
		data.stream_by_id.house4_part0[field]=17
		frozen=data.duplicate(true);var snapshot:=library.duplicate(true)
		check(not Index.retire_owned(data,library,["road"]).ok and data==frozen and library==snapshot,"unchanged survivor "+field+" corruption still rejects atomically")
	print("OWNED_RETIREMENT_PLAN checks=",checks," failures=",failures);quit(1 if failures else 0)
