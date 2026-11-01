extends "res://tools/test_private_publication_packet.gd"
const Startup=preload("res://scripts/world3d/residency_startup.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const MODEL="fixture_shared_native.scn"
var late:=false
var results:Array=[]
class Host extends Node:
	var _ready_for_play:=false
	var _transfer_pending:=true
	var _navigation:Node

func make_map(host:Node,indexed:bool=true,adopted:bool=true)->Dictionary:
	var map_root:=Node3D.new();host.add_child(map_root)
	var queue:=Deferred.new();queue.name="DeferredAssets";map_root.add_child(queue);queue._map=map_root;queue.set_process(false)
	var records:Array=[];var entries:Array=[]
	for uuid:String in ["guild","annex"]:
		var record:={"uuid":uuid,"kind":"asset","asset_path":MODEL}
		records.append(record)
		entries.append({"uuid":uuid,"order":records.size()-1,"bounds_known":true,"group_id":"","asset_path":MODEL,"bounds":AABB(Vector3.ZERO,Vector3.ONE),"classification":"spatial","reason":"asset","memory_bytes":0})
	if indexed:queue._reference_index={"rows":entries,"extras":{"rmmo_records":records},"groups":{}}
	map_root.set_meta("extras",{"rmmo_records":records});map_root.set_meta("stream_library",[])
	map_root.set_meta("stream_children",map_root.get_child_count(true) if adopted else -1)
	return {"map":map_root,"queue":queue}

func setup(map_fixture:Dictionary,host:Node)->Dictionary:
	var before:int=map_fixture.map.get_meta("stream_library",[]).size()
	var began:=Time.get_ticks_usec();var ok:=Startup.ensure(host,map_fixture.map)
	var elapsed:=Time.get_ticks_usec()-began
	return {"ok":ok,"bootstrap_library_rows":before,"us":elapsed}

func prepared_source(mesh:Mesh,namespace_:String,count:int)->Dictionary:
	var specs:Array=values(mesh)
	if count<specs.size():specs.resize(count)
	if namespace_!="guild":
		for i:int in specs.size():
			specs[i].uuid="%s__part%d"%[namespace_,i]
			specs[i].extras.building.id=namespace_
	return prepare_rows(specs,namespace_)

func prepare_rows(specs:Array,label:String)->Dictionary:
	var prep:=Prep.new();prep.begin_runtime_owned(specs)
	while not prep.advance(500):pass
	check(prep.valid_runtime_owned(specs),label+" private publication metadata prepared")
	return {"specs":specs,"prep":prep,"packet":prep.publication_packet}

func publish_fixture(map_fixture:Dictionary,prepared:Dictionary,index:Dictionary)->int:
	for key:String in index:map_fixture.map.set_meta(key,index[key])
	map_fixture.map.set_meta("stream_library",index.stream_by_id.values())
	map_fixture.queue.publication_metadata=prepared.packet
	var began:=Time.get_ticks_usec();map_fixture.queue.published.emit(prepared.specs)
	var elapsed:=Time.get_ticks_usec()-began
	map_fixture.queue.publication_metadata=null
	return elapsed

func state(map_fixture:Dictionary)->Dictionary:
	var ordinary:Node=map_fixture.map.get_node("AssetResidency")
	var native:Node=map_fixture.map.get_node("NativeResidency")
	return {"source_ids":ordinary._spec_namespaces.duplicate(),"namespaces":ordinary._namespace_specs.duplicate(true),"models":ordinary._model_namespaces.duplicate(true),"ordinary_resident":ordinary._resident.duplicate(true),"native_namespaces":ordinary._native_namespaces.duplicate(),"native":native._resident.duplicate(true),"owners":native._owners.duplicate(),"units":native._units.duplicate(true),"bounds":map_fixture.queue._runtime_building_records.duplicate(true),"supports":map_fixture.queue._runtime_building_supports.duplicate(true)}

func counts(map_fixture:Dictionary)->Dictionary:
	return {"ordinary":int(map_fixture.map.get_node("AssetResidency").profile.get("prepared_observations",0)),"native":int(map_fixture.map.get_node("NativeResidency").profile.get("prepared_observations",0))}

func test_startup_and_publication()->void:
	var host:=Host.new();root.add_child(host)
	var control:=make_map(host);var candidate:=make_map(host)
	var first_setup:Dictionary={}
	if not late:first_setup=setup(candidate,host)
	var source:=prepared_source(CountedMesh.new(),"guild",2151)
	var index:Dictionary=Index.build([])
	check(Index.append(index,source.specs,source.prep).ok,"actual prepared StreamIndex commit succeeds")
	var support:={"uuid":"ground__part","ground_batch_record":{"uuid":"ground"}}
	for spec:Dictionary in source.specs:spec.render_supports=[support]
	var candidate_publish_us:=publish_fixture(candidate,source,index)
	publish_fixture(control,source,index)
	var control_setup:=setup(control,host)
	if late:first_setup=setup(candidate,host)
	check(first_setup.ok and control_setup.ok and state(candidate)==state(control),"early subscription and late configure have identical IDs, models, bounds, support and native handoff")
	var observed:=counts(candidate)
	check(observed.ordinary==1 and observed.native==1,"entry publication reaches both prepared observers before metadata is discarded")
	check(int(first_setup.bootstrap_library_rows)==0 and int(control_setup.bootstrap_library_rows)==2151,"entry startup avoids replaying all accumulated parts at late configure")
	var ordinary:Node=candidate.map.get_node("AssetResidency");var native:Node=candidate.map.get_node("NativeResidency")
	check(ordinary._resident.is_empty() and ordinary.model_in_use(MODEL) and native._resident["asset:guild"].ids.size()==2151,"native takeover keeps one shared-model lease and all 2151 identities")
	check(native._units["asset:guild"].support_ids.has("ground") and candidate.queue._runtime_building_supports.guild.has("ground"),"prepared observer receives support bound after index preparation")
	check(native._units["asset:guild"].bounds==control.map.get_node("NativeResidency")._units["asset:guild"].bounds,"prepared observer retains the full live building envelope")
	var before:=state(candidate);var before_counts:=counts(candidate);var ordinary_id:=ordinary.get_instance_id();var native_id:=native.get_instance_id()
	for i:int in 3:check(Startup.ensure(host,candidate.map),"repeated startup remains available")
	check(state(candidate)==before and counts(candidate)==before_counts and ordinary_id==candidate.map.get_node("AssetResidency").get_instance_id() and native_id==candidate.map.get_node("NativeResidency").get_instance_id(),"ensure is idempotent without rescanning or replacing owners")
	check(candidate.queue.published.get_connections().size()==2 and int(candidate.map.get_meta("stream_children"))==candidate.map.get_child_count(true),"two consumers connect once and completed child adoption remains current")
	var addition:=prepared_source(BoxMesh.new(),"annex",37)
	check(Index.append(index,addition.specs,addition.prep).ok,"subsequent private namespace commits to the same index")
	for spec:Dictionary in addition.specs:spec.render_supports=[support]
	publish_fixture(candidate,addition,index);publish_fixture(control,addition,index)
	check(state(candidate)==state(control) and ordinary._model_namespaces[MODEL].size()==2,"later publication preserves exact ownership and shares one model across two namespaces")
	check(counts(candidate).ordinary==observed.ordinary+1 and counts(candidate).native==observed.native+1,"later publication still uses each prepared consumer exactly once")
	ordinary.forget_specs(source.packet.ids.keys())
	check(ordinary.model_in_use(MODEL) and ordinary._model_namespaces[MODEL].size()==1,"retiring one namespace retains the other model user")
	ordinary.forget_specs(addition.packet.ids.keys())
	check(not ordinary.model_in_use(MODEL),"retiring the final namespace releases shared model usage")
	results.append({"late":late,"first_setup":first_setup,"control_setup":control_setup,"candidate_publish_us":candidate_publish_us,"first_prepared_observations":observed,"parts":2151,"additional_parts":37})
	# Keep the signal source alive across owner destruction, so automatic
	# disconnect is observed directly rather than hidden by destroying it too.
	var old_queue:Node=candidate.queue;candidate.map.remove_child(old_queue)
	candidate.map.free()
	check(old_queue.published.get_connections().is_empty() and not is_instance_valid(ordinary) and not is_instance_valid(native),"retired map leaves no residency callback on a surviving old queue")
	var replacement:=make_map(host)
	check(Startup.ensure(host,replacement.map) and replacement.queue.published.get_connections().size()==2 and old_queue.published.get_connections().is_empty(),"replacement map owns only its own two subscriptions")
	old_queue.published.emit([]);old_queue.free()
	source.prep.dispose();addition.prep.dispose();host.free()

func test_adoption_and_no_index()->void:
	var host:=Host.new();root.add_child(host)
	var pending:=make_map(host,true,false)
	check(Startup.ensure(host,pending.map) and int(pending.map.get_meta("stream_children"))==-1,"incomplete child adoption stays invalidated after residency nodes are added")
	var plain:=make_map(host,false,true);var count:int=plain.map.get_child_count(true)
	check(not Startup.ensure(host,plain.map) and plain.map.get_child_count(true)==count and plain.queue.published.get_connections().is_empty(),"non-indexed loader retains its existing path without residency nodes or subscriptions")
	host.free()

func building_state(map_fixture:Dictionary)->Dictionary:
	var native:Node=map_fixture.map.get_node("NativeResidency")
	return {"bounds":native._units["asset:guild"].bounds,"support_ids":native._units["asset:guild"].support_ids.duplicate(),"runtime_bounds":map_fixture.queue._runtime_building_records.guild,"runtime_supports":map_fixture.queue._runtime_building_supports.guild.duplicate(),"ids":native._resident["asset:guild"].ids.duplicate()}

func test_building_before_ground()->void:
	var host:=Host.new();root.add_child(host)
	var early:=make_map(host);var control:=make_map(host)
	var ground_record:={"uuid":"late_ground","kind":"box","surface_id":"ground","size":[256,1,256]}
	for map_fixture:Dictionary in [early,control]:
		var directory:Dictionary=map_fixture.queue._reference_index
		directory.extras.rmmo_records.append(ground_record)
		directory.rows.append({"uuid":"late_ground","order":2,"bounds_known":true,"group_id":"","asset_path":"","bounds":AABB(Vector3(-64,-1,-64),Vector3(256,1,256)),"classification":"spatial","reason":"native_box","memory_bytes":0})
		var empty_index:Dictionary=Index.build([])
		for key:String in empty_index:map_fixture.map.set_meta(key,empty_index[key])
	check(Startup.ensure(host,early.map),"building-before-ground fixture subscribes before the first append")
	var source:=prepared_source(CountedMesh.new(),"guild",2151)
	var building_append:Dictionary=Stream.append_specs(early.map,source.specs,source.prep)
	check(building_append.ok,"building enters through real WorldStream.append_specs")
	early.queue.publication_metadata=source.packet;early.queue.published.emit(source.specs);early.queue.publication_metadata=null
	var before:=building_state(early)
	var ground_mesh:=BoxMesh.new();ground_mesh.size=Vector3(256,1,256)
	var terrain:Array=[{"uuid":"late_ground","chunk":Vector2i(-2,-2),"chunk_min":Vector2i(-2,-2),"chunk_max":Vector2i(5,5),"transform":Transform3D(Basis.IDENTITY,Vector3(64,-.5,64)),"mesh":ground_mesh,"extras":{},"ground_batch_record":ground_record}]
	# Landscape has mutable reverse dependency links and deliberately uses the
	# normal copied preparation, matching the production ground append path.
	var terrain_prep:=Prep.new();terrain_prep.begin(terrain)
	while not terrain_prep.advance(500):pass
	var terrain_append:Dictionary=Stream.append_specs(early.map,terrain,terrain_prep)
	check(terrain_append.ok and terrain_append.get("affected_existing_specs",[]).size()==2151,"large later ground invalidates all 2151 already published building parts: "+str(terrain_append.get("reason","")))
	# Match the production publication contract: listeners receive additions,
	# while the Stream commit itself owns updates to existing group envelopes.
	early.queue.publication_metadata=terrain_prep.publication_packet;early.queue.published.emit(terrain);early.queue.publication_metadata=null
	for key:StringName in early.map.get_meta_list():
		if str(key).begins_with("stream_"):control.map.set_meta(key,early.map.get_meta(key))
	check(Startup.ensure(host,control.map),"late initialization sees the final ground/building index")
	var after:=building_state(early);var expected:=building_state(control)
	check(expected.bounds!=before.bounds and expected.support_ids.has("late_ground"),"later ground really expands the building envelope and introduces a support")
	check(after.bounds==expected.bounds and after.support_ids==expected.support_ids,"early native unit receives existing-building bounds and support delta")
	check(after.runtime_bounds==expected.runtime_bounds and after.runtime_supports==expected.runtime_supports,"early runtime building registration matches late initialization after ground append")
	check(after.ids==before.ids and after.ids==expected.ids and after.ids.size()==2151,"dependency refresh preserves every building identity without duplicate publication")
	var native:Node=early.map.get_node("NativeResidency")
	check(terrain_append.affected_existing_groups.size()==1 and native.profile.dependency_group_updates==1 and native.profile.dependency_unit_updates==1,"2151 changed components refresh one group and one owner")
	var before_reject:=building_state(early);var before_profile:Dictionary=native.profile.duplicate(true)
	var rejected:Dictionary=Stream.append_specs(early.map,terrain)
	check(not rejected.ok and building_state(early)==before_reject and native.profile==before_profile,"rejected duplicate append leaves dependency state and work counters unchanged")
	for summary:Dictionary in [before,after,expected]:
		summary.parts=summary.ids.size();summary.erase("ids")
	results.append({"case":"building_before_ground","affected_existing_specs":terrain_append.get("affected_existing_specs",[]).size(),"before":before,"early":after,"late":expected})
	source.prep.dispose();terrain_prep.dispose();host.free()

func test_shared_group_and_reappend()->void:
	var host:=Host.new();root.add_child(host)
	var early:=make_map(host);var control:=make_map(host)
	for map_fixture:Dictionary in [early,control]:
		var initial:Dictionary=Index.build([])
		for key:String in initial:map_fixture.map.set_meta(key,initial[key])
	check(Startup.ensure(host,early.map),"shared-group owners subscribe before append")
	var specs:Array=values(CountedMesh.new());specs.resize(2)
	for i:int in specs.size():
		specs[i].uuid=("guild" if i==0 else "annex")+"__part0"
		specs[i].extras.erase("fixture")
	var source:=prepare_rows(specs,"two namespace shared group")
	check(Stream.append_specs(early.map,specs,source.prep).ok,"two namespaces commit one complete shared building group")
	early.queue.publication_metadata=source.packet;early.queue.published.emit(specs);early.queue.publication_metadata=null
	var terrain:Array=[{"uuid":"shared_ground","chunk_min":Vector2i(-1,-1),"chunk_max":Vector2i(3,3),"transform":Transform3D.IDENTITY,"mesh":BoxMesh.new(),"extras":{},"ground_batch_record":{"uuid":"shared_ground","kind":"box","surface_id":"ground","size":[160,1,160]}}]
	var appended:Dictionary=Stream.append_specs(early.map,terrain)
	check(appended.ok and appended.affected_existing_groups.size()==1,"one later ground changes the shared group")
	early.queue.published.emit(terrain)
	for key:StringName in early.map.get_meta_list():
		if str(key).begins_with("stream_"):control.map.set_meta(key,early.map.get_meta(key))
	check(Startup.ensure(host,control.map),"shared-group late initialization succeeds")
	var native:Node=early.map.get_node("NativeResidency");var reference:Node=control.map.get_node("NativeResidency")
	check(native._group_units.guild.size()==2 and native.profile.dependency_group_updates==1 and native.profile.dependency_unit_updates==2,"shared group refreshes both owners with one group observation")
	for unit:String in ["asset:guild","asset:annex"]:
		check(native._units[unit].bounds==reference._units[unit].bounds and native._units[unit].support_ids==reference._units[unit].support_ids and native._units[unit].support_ids.has("shared_ground"),"shared group early/late support equality for "+unit)
	# There are no rendering jobs in this headless component. Mark its append
	# planning complete and use a distant demand; keep real retirement preflight.
	early.map.set_meta("stream_append_pending",[]);early.map.set_meta("stream_chunk",Vector2i(100,100))
	var retired:Dictionary=Stream.retire_specs(early.map,source.packet.ids.keys(),true)
	check(retired.ok and not native._group_units.has("guild"),"successful complete retirement removes the shared group owner cache")
	var replacement:Array=values(CountedMesh.new());replacement.resize(1)
	replacement[0].uuid="annex__part0";replacement[0].extras.erase("fixture")
	var replacement_prep:=prepare_rows(replacement,"replacement namespace")
	var reapplied:Dictionary=Stream.append_specs(early.map,replacement,replacement_prep.prep)
	check(reapplied.ok,"retired group identity can be appended again")
	early.queue.publication_metadata=replacement_prep.packet;early.queue.published.emit(replacement);early.queue.publication_metadata=null
	check(native._group_units.guild=={"asset:annex":true},"reappended group remembers only its current owner without the retired namespace")
	source.prep.dispose();replacement_prep.prep.dispose();host.free()

func run()->void:
	late="--late" in OS.get_cmdline_user_args()
	test_startup_and_publication()
	test_adoption_and_no_index()
	test_building_before_ground()
	test_shared_group_and_reappend()
	var report:={"failures":failures,"late":late,"cases":results,"scope":"2151-part prepared publication, residency startup/ownership lifecycle; component timing is not a map score"}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ENTRY_RESIDENCY_STARTUP ",JSON.stringify(report));quit(1 if failures else 0)
