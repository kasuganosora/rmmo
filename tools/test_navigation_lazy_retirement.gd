extends "res://tools/test_sliced_native_retirement.gd"
const Nav=preload("res://scripts/world3d/world_navigation.gd")
func run()->void:
	var trials:Array=[]
	for lazy:bool in [false,true,true,false]:
		Nav.lazy_retirement_snapshot_enabled=lazy
		var f:=setup();var selected:Array=f.ids.slice(0,100);var before:Array=f.nav._specs.duplicate()
		var began:=Time.get_ticks_usec()
		for at:int in range(0,2200,100):
			var result:Dictionary=f.nav.try_retire_specs(f.ids.slice(at,at+100))
			check(result.ok,"separate retirement transaction completes")
		var elapsed:=Time.get_ticks_usec()-began
		var rows:int=f.nav.loading_profile.get("retirement_snapshot_rows",0)
		check(f.nav._spec_ids.size()==2400,"logical membership removes every retired UUID immediately")
		check(f.nav._specs==f.library.slice(2200),"first consumer sees exact ordered survivors")
		check(before==f.library,"borrowed pre-retirement array retains its contents")
		check(f.nav.append_specs(f.library.slice(0,100)).ok,"same UUIDs can return after materialization")
		check(f.nav.try_retire_specs(selected).ok,"returned UUIDs retire again")
		check(f.nav.append_specs(f.library.slice(0,100)).ok,"append into dirty catalogue succeeds without forcing its snapshot")
		check(f.nav._specs==f.library.slice(2200)+f.library.slice(0,100),"append after dirty retirement preserves canonical order")
		trials.append({"lazy":lazy,"us":elapsed,"snapshot_rows_during_retirement":rows})
		f.map.free();f={};before=[];drain()
	check(trials[0].snapshot_rows_during_retirement==75900 and trials[1].snapshot_rows_during_retirement==0,"22 retirements avoid rebuilding 75900 surviving source rows")
	Nav.lazy_retirement_snapshot_enabled=true
	# No outstanding borrowed array/library: dirty state must not retain a mesh.
	var f:=setup();var watch:WeakRef=f.watch
	check(f.nav.try_retire_specs(f.ids).ok,"isolated ownership removal succeeds")
	var map_owner:Node=f.map
	for key:StringName in map_owner.get_meta_list():map_owner.remove_meta(key)
	f={};drain()
	check(watch.get_ref()==null,"lazy snapshot leaves no retired resource owner")
	map_owner.free()
	print("NAVIGATION_LAZY_RETIREMENT ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)
