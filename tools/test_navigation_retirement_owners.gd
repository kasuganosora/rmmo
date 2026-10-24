extends "res://tools/test_sliced_native_retirement.gd"
const Nav=preload("res://scripts/world3d/world_navigation.gd")
func run()->void:
	var trials:Array=[]
	for fast:bool in [false,true,true,false]:
		Nav.coalesced_retirement_owners_enabled=fast
		var f:=setup();var mesh:Mesh=f.library[0].mesh
		f.nav._faces[mesh.get_instance_id()]=PackedVector3Array([Vector3.ONE])
		var began:=Time.get_ticks_usec();var result:Dictionary=f.nav.try_retire_specs(f.ids)
		trials.append({"coalesced":fast,"us":Time.get_ticks_usec()-began,"owner_updates":f.nav.loading_profile.retirement_geometry_updates})
		check(result.ok and result.removed==2200 and f.nav._specs==f.library.slice(2200),"complete namespace removal preserves ordered survivors")
		check(not f.nav._faces.has(mesh.get_instance_id()) and not f.nav._geometry_users.has(mesh.get_instance_id()),"last geometry owner removes exact cached faces")
		check(f.nav.append_specs(f.library.slice(0,2200)).ok,"same UUIDs and geometry can return")
		check(f.nav._geometry_users[mesh.get_instance_id()]==2200,"return restores exact geometry count")
		f.map.free();f={};drain()
	Nav.coalesced_retirement_owners_enabled=true
	print("NAVIGATION_RETIREMENT_OWNERS ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)
