extends "res://tools/test_sliced_native_retirement.gd"
const Nav=preload("res://scripts/world3d/world_navigation.gd")
const Packet=preload("res://scripts/world3d/publication_metadata.gd")

func run()->void:
	Stream.resident_retirement_catalog_enabled=true
	var timings:Array=[]
	for fast:bool in [false,true,true,false]:
		Index.ordered_retirement_catalog_enabled=fast;Nav.ordered_retirement_catalog_enabled=fast
		var f:=setup();var alias:Array=f.library;var expected:Array=f.library.slice(2200)
		await process_frame
		var began:=Time.get_ticks_usec()
		var result:=Stream.retire_specs(f.map,f.ids,true,f.nav,"native_retirement")
		var elapsed:=Time.get_ticks_usec()-began
		check(result.ok and is_same(alias,f.library) and alias.size()==2400,"atomic unload preserves the externally held library Array")
		check(f.library==expected and f.nav._specs==expected,"index and navigation preserve the exact survivor order")
		for i:int in expected.size():
			if not is_same(f.library[i],expected[i]) or not is_same(f.nav._specs[i],expected[i]):check(false,"survivor identity changed");break
		check(f.watch.get_ref()!=null,"retirement queue holds removed geometry until disposal")
		drain();check(f.watch.get_ref()==null,"ordered catalogs release all retired geometry")
		var returned:=spec("guild__return",Vector2i(50,50),Vector2i(50,50),{"kind":"asset"})
		check(Stream.append_specs(f.map,[returned]).ok and f.nav.append_specs([returned]).ok,"a retired namespace can append again")
		check(is_same(f.library[-1],returned) and is_same(f.nav._specs[-1],returned),"return appends at the end in both ordered catalogs")
		f.map.set_meta("stream_append_pending",[]);await process_frame
		check(Stream.retire_specs(f.map,["guild__return"],true,f.nav,"native_retirement").ok,"returned namespace retires again")
		timings.append({"ordered":fast,"elapsed_us":elapsed,"removed":2200,"survivors":2400})
		f.map.free();f={};drain()
	Index.ordered_retirement_catalog_enabled=true;Nav.ordered_retirement_catalog_enabled=true
	public_order();full_bake_ownership()
	print("ORDERED_RETIREMENT_CATALOG ",JSON.stringify(timings)," failures=",failures)
	quit(1 if failures else 0)

func public_order()->void:
	var f:Dictionary=fixture();f.library.reverse()
	var expected:Array=[]
	for item:Dictionary in f.library:
		if not item.uuid.begins_with("guild__"):expected.append(item)
	check(Index.retire_owned(f.data,f.library,f.ids).ok and f.library==expected,"public mutable library keeps its current order rather than dictionary insertion order")

func full_bake_ownership()->void:
	var nav:=Nav.new();root.add_child(nav);nav.set_process(false)
	nav.geometry_pending=true;nav.map=NavigationServer3D.map_create()
	var private_mesh:=BoxMesh.new();var watch:WeakRef=weakref(private_mesh)
	var rows:Array=[spec("full_map",Vector2i.ZERO,Vector2i.ZERO,{})];rows[0].mesh=private_mesh
	var packet:=Packet.new();packet.begin(rows);packet.add(rows[0],private_mesh.get_aabb())
	check(nav.append_specs(rows,packet).ok and nav._spec_ids.full_map==true,"non-streaming prepared append keeps scalar identity bookkeeping")
	packet=null;rows=[];private_mesh=null;nav._specs=[]
	check(watch.get_ref()==null,"completed full bake has no hidden mesh owner in its identity set")
	nav.free()
