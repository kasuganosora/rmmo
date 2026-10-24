extends "res://tools/test_sliced_native_retirement.gd"
func retire(nav:Node,ids:Array,selected:Dictionary,borrow:bool)->Dictionary:
	return nav.call("_try_retire_index_selection",selected) if borrow and nav.has_method("_try_retire_index_selection") else nav.try_retire_specs(ids)
func run()->void:
	var trials:Array=[]
	for borrow:bool in [false,true,true,false]:
		var f:=setup();var selected:Dictionary={}
		for id:String in f.ids:selected[id]=true
		var before:=selected.duplicate();var elapsed:=0
		for repeat:int in 12:
			var start:=Time.get_ticks_usec();var result:=retire(f.nav,f.ids,selected,borrow);elapsed+=Time.get_ticks_usec()-start
			check(result.ok and result.removed==2200 and f.nav._specs==f.library.slice(2200),"ordered sources retire identically")
			check(selected==before,"borrowed selection remains unchanged")
			check(f.nav.append_specs(f.library.slice(0,2200)).ok,"retired namespace can return")
		trials.append({"borrow":borrow,"us":elapsed,"selection_entries_created":f.nav.loading_profile.get("retirement_selection_entries",0)})
		for guard:String in ["ready_for_queries","_resizing","_publish_wait","_deferred_full_publish"]:
			var previous:Variant=f.nav.get(guard);f.nav.set(guard,false if guard=="ready_for_queries" else (1 if guard=="_publish_wait" else true))
			var result:=retire(f.nav,f.ids,selected,borrow)
			check(not result.ok and f.nav._specs.size()==4600 and f.nav._spec_ids.size()==4600,"busy "+guard+" rejects without changing sources")
			f.nav.set(guard,previous)
		var invalid:=selected.duplicate();invalid["unknown"]=true
		check(not retire(f.nav,invalid.keys(),invalid,borrow).ok and f.nav._spec_ids.size()==4600,"unknown navigation source rejects before mutation")
		f.map.free();f={};drain()
	print("NAVIGATION_RETIREMENT_SELECTION ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)
