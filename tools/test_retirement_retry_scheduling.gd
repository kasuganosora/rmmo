extends "res://tools/test_native_retirement_scheduling.gd"
## Small CPU-only real index/navigation transactions; no sleeps, models or GPU.
const Native=preload("res://scripts/world3d/native_residency.gd")
const Ordinary=preload("res://scripts/world3d/asset_residency.gd")
class PlayingHost extends Host:
	var _ready_for_play:=true
	var _transfer_pending:=false
class ProbeQueue extends Queue:
	func runtime_record(_id:String)->Dictionary:return {}
class ObservedOrdinary extends Ordinary:
	var selected_rows:=0
	func _retirement_selection(uuids:Array)->Dictionary:
		var result:=super._retirement_selection(uuids);selected_rows+=result.ids.size();return result
class ObservedNative extends Native:
	var selected_rows:=0
	func _retirement_selection(units:Array)->Dictionary:
		var result:=super._retirement_selection(units);selected_rows+=result.ids.size();return result
	var observations:=0
	func _retirement_candidates(now:int)->Array:
		observations+=1
		return super._retirement_candidates(now)
class CacheScope extends RefCounted:
	func release(_path:String)->bool:return true
func next_frame()->void:
	var previous:=Engine.get_process_frames()
	while Engine.get_process_frames()==previous:await process_frame
func fixture(native_count:int=16,asset_count:int=16)->Dictionary:
	var host:=PlayingHost.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map)
	var queue:=ProbeQueue.new();map.add_child(queue)
	queue._doc.load_box_meshes={};queue._doc.load_material_pool={};queue._doc.load_surface_arrays={}
	var native:=ObservedNative.new();native.name="NativeResidency";map.add_child(native);native.set_process(false)
	native._host=host;native._map=map;native._queue=queue;native.grace_msec=10
	var ordinary:=ObservedOrdinary.new();ordinary.name="AssetResidency";map.add_child(ordinary);ordinary.set_process(false)
	ordinary._host=host;ordinary._map=map;ordinary._deferred=queue;ordinary.grace_msec=10
	var library:Array=[];var records:Array=[]
	for i:int in native_count:
		var id:="native%d"%i;var record:={"uuid":id,"kind":"box"};records.append(record)
		library.append(spec(id,Vector2i(100,0),Vector2i(100,0),record))
		native._units[id]={"entries":[{"compact_record":record,"asset_path":"","reason":"native_box"}],"bounds":AABB(Vector3(3200+i,0,0),Vector3.ONE),"kind":"all"}
		native._resident[id]={"ids":[id],"outside_since":0}
	for i:int in asset_count:
		var id:="asset%d"%i;var record:={"uuid":id,"kind":"asset","asset_path":"shared.glb"};records.append(record)
		ordinary._catalog[id]={"compact_record":record,"asset_path":"shared.glb","bounds":AABB(Vector3(3200+i,0,0),Vector3.ONE)}
		ordinary._remember_traits(record);library.append(spec(id+"__part",Vector2i(100,0),Vector2i(100,0),record))
	map.set_meta("stream_library",library);map.set_meta("extras",{"rmmo_records":records})
	var data:=Index.build(library)
	for key:String in data:map.set_meta(key,data[key])
	map.set_meta("stream_chunk",Vector2i.ZERO);map.set_meta("runtime_asset_cache_scope",CacheScope.new())
	ordinary.observe(library)
	for state:Dictionary in ordinary._resident.values():state.outside_since=0
	var nav:=preload("res://scripts/world3d/world_navigation.gd").new();host.add_child(nav);host._navigation=nav
	nav.configure_streaming_geometry(func(_clip:AABB):return {"ok":true,"error":""})
	nav.map=NavigationServer3D.map_create();nav.ready_for_queries=true;nav.set_process(false)
	check(nav.append_specs(library).ok,"fixture navigation owns complete source identities")
	return {"host":host,"map":map,"queue":queue,"native":native,"ordinary":ordinary,"nav":nav,"library":library}
func overrun(f:Dictionary,lane:String)->void:
	# Account a declared indivisible 3 ms cost without doing 3 ms of busy work.
	Stream.charge_retirement_work(f.map,lane,Time.get_ticks_usec()-3000)
func run()->void:
	var f:=fixture();await next_frame()
	f.ordinary._process(.25);overrun(f,"ordinary_retirement");f.native._process(.25)
	check(f.ordinary.profile.retired_instances==8 and f.native.profile.retired_units==0,"ordinary overrun protects all denied native sources in the first observation")
	check(f.native.selected_rows==0,"budget denial builds zero native selected-part rows")
	var native_cursor:int=f.native._cursor;var ordinary_cursor:int=f.ordinary._cursor
	await next_frame();f.ordinary._process(.001);f.native._process(.001)
	check(f.native.profile.retired_units==8,"denied mature native batch retries on the next frame without 250 ms delay")
	overrun(f,"native_retirement")
	for turn:int in 6:
		await next_frame()
		var before_ordinary:int=f.ordinary.profile.retired_instances
		f.ordinary._process(.001)
		if f.ordinary.profile.retired_instances>before_ordinary:overrun(f,"ordinary_retirement")
		var before_native:int=f.native.profile.retired_units
		f.native._process(.001)
		if f.native.profile.retired_units>before_native:overrun(f,"native_retirement")
	check(f.library.is_empty() and f.nav._spec_ids.is_empty() and f.queue.pending.size()==32,"both real ownership lanes drain all mature candidates within eight fresh frames")
	check(f.native.observations==1 and f.native._cursor==native_cursor and f.ordinary._cursor==ordinary_cursor,"frame retries never rescan the resident directory or advance observation cursors")
	var budget:Dictionary=Stream._retirement_budget(f.map).snapshot()
	check(budget.current_limit_us==2000 and budget.protected_grants>0,"next-frame progress keeps the original 2 ms ledger and protected fair turns")
	f.host.free();await next_frame()
	# A map-wide barrier is unchanged inside one synchronous callback.
	f=fixture(16,0);f.map.set_meta("stream_candidate_work",{})
	f.native._process(.25)
	check(int(f.native.profile.get("retirement_attempts",0))==1,"native stream_busy is checked only once in one poll")
	var attempts:int=f.native.profile.get("retirement_attempts",0)
	await next_frame();f.native._process(.001)
	check(int(f.native.profile.get("retirement_attempts",0))==attempts+1 and f.native.observations==1,"busy retry is one bounded fresh-frame attempt without another observation")
	check(f.library.size()==16 and f.nav._spec_ids.size()==16 and f.queue.pending.is_empty(),"busy retries never partly retire or requeue an ownership unit")
	check(f.native.selected_rows==0,"repeated busy frames materialise zero selected-part rows")
	f.map.remove_meta("stream_candidate_work");await next_frame();f.native._process(.001)
	check(f.native.profile.retired_units==8,"clearing the busy barrier resumes a complete mature batch next frame")
	f.host.free();await next_frame()
	# A moving player invalidates cached eligibility before any commit.
	f=fixture();overrun(f,"ordinary_retirement")
	f.ordinary._process(.25);f.native._process(.25)
	f.queue._demands={"returned":{"kind":"all","clip":AABB(Vector3(3100,0,-100),Vector3(300,1,300))}}
	await next_frame();f.ordinary._process(.001);f.native._process(.001)
	check(f.library.size()==32 and f.queue.pending.is_empty(),"new live demand protects every cached native and ordinary candidate")
	check(f.native._resident.native0.outside_since==-1 and f.ordinary._resident.asset0.outside_since==-1,"returned demand resets both grace clocks before queued eligibility can be reused")
	f.queue._demands.clear();f.ordinary._process(.25);f.native._process(.25)
	check(f.library.size()==32,"leaving again cannot reuse the previous visit's matured grace")
	f.host.free();await next_frame()
	# Late jobs/pending reconstruction preserve source ownership.
	f=fixture();overrun(f,"ordinary_retirement");f.ordinary._process(.25);f.native._process(.25)
	f.queue._jobs["shared.glb"]={};f.queue.pending.append({"record":{"uuid":"native0"}})
	for turn:int in 4:await next_frame();f.ordinary._process(.001);f.native._process(.001)
	check(f.ordinary._resident.size()==16 and f.native._resident.has("native0"),"late shared-model job and pending native record veto stale cached candidates")
	check(f.native.profile.retired_units==15,"a pending native owner does not starve unrelated mature neighbours")
	f.queue._jobs.clear();f.host.free();await next_frame()
	# A busy map with many resident owners still retries only the saved slice.
	f=fixture(80,96);f.map.set_meta("stream_candidate_work",{})
	f.ordinary._process(.25);f.native._process(.25)
	check(f.native._retry_candidates.size()==16 and f.ordinary._retry_candidates.size()==32,"mature retry queues contain only one bounded observation slice")
	for turn:int in 5:await next_frame();f.ordinary._process(.001);f.native._process(.001)
	check(f.native.observations==1 and f.native._cursor==16 and f.ordinary._cursor==32,"busy frames do not scan the other 128 resident owners")
	check(f.native.selected_rows==0 and f.ordinary.selected_rows==0,"both blocked services build zero selected rows across repeated frames")
	f.map.remove_meta("stream_candidate_work");f.host.free();await process_frame
	# Diagnostic A/B keeps exactly the same commit/validation code at 250 ms.
	Native.frame_retry_enabled=false;Ordinary.frame_retry_enabled=false
	f=fixture();await next_frame();f.ordinary._process(.25);overrun(f,"ordinary_retirement");f.native._process(.25)
	await next_frame();f.ordinary._process(.001);f.native._process(.001)
	check(f.ordinary.profile.retired_instances==8 and f.native.profile.retired_units==0,"diagnostic control retains quarter-second dispatch without bypassing the ledger")
	f.host.free();await process_frame
	Native.frame_retry_enabled=true;Ordinary.frame_retry_enabled=true
	print("RETIREMENT_RETRY_SCHEDULING checks=",checks," failures=",failures);quit(1 if failures else 0)