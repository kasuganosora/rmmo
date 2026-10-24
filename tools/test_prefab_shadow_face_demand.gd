extends "res://tools/test_house_geometry_identity_reuse.gd"
## Regression for demand-selected render faces and shared white-model preparation.
const ShadowDemand=preload("res://scripts/world3d/prefab_shadow_face_demand.gd")
const Shadow=preload("res://scripts/world3d/building_shadow_proxy.gd")
var old_shadow_control:=false

func full_reference_contract(value:Dictionary)->void:
	const Index=preload("res://scripts/world3d/map_dependency_index.gd")
	const Paths=preload("res://scripts/world3d/map_paths.gd")
	var helper:=preload("res://tools/test_map_dependency_index.gd").new()
	helper.content_root=Paths.external_root();helper.folder=Paths.cache_directory("shadow167_reference_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(helper.folder)
	var bridge:=preload("res://scripts/world_editor/bridge_tools.gd").make_record({"id":"nonbuilding_first","start":[-6,0,0],"end":[6,0,0]},preload("res://scripts/world3d/bridge_data.gd").preset("stone_segmental"))
	# The frozen payload is authoritative; its bridge recipe is provenance.
	bridge.house_prefab=value;bridge.prefab_locked=true;bridge.prefab_materials=[]
	var building:=record(value,"building_second");building.prefab_locked=true;building.prefab_materials=[]
	building.building={"id":"house","part":"shell","role":"shell","floor":0,"floor_y":0}
	var meta:={"building_instances":{"house":{"version":Index.Blueprint.VERSION,"parameters":Index.Blueprint.defaults(),"position":[0,0,0],"yaw":0,"parts":{"shell":"building_second"},"signatures":{"shell":"fixture"},"baked":true}}}
	var records:Array=[bridge,building];var fixture_file:Dictionary=helper.fixture("mixed",records,meta)
	check(not fixture_file.is_empty(),"temporary mixed reference package is written outside project")
	if fixture_file.is_empty():helper.free();return
	var index:=Index.build(fixture_file.path,helper.content_root,records,"",1,16777216,true)
	check(index.ok,"actual directory accepts nonbuilding bridge then complete building")
	if not index.ok:print("SHADOW167_INDEX_FAILURE ",index);helper.free();return
	var requests:Array=[]
	for row:Dictionary in index.rows:
		requests.append({"record_index":row.order,"compact_record":index.extras.rmmo_records[row.order],"bounds":index.groups[row.group_id].bounds if not row.group_id.is_empty() else row.bounds,"group_id":row.group_id,"asset_path":row.asset_path})
	House.evict_geometry({value.sha256:true});evict(value.sha256)
	var before:=FileAccess.get_sha256(fixture_file.path);var task:=Thread.new()
	task.start(Prepare.prepare.bind(index,requests,fixture_file.path,helper.content_root,null,null,{}, {},0,true))
	var result:Dictionary=task.wait_to_finish()
	check(result.error.is_empty(),"full chunk transaction succeeds on existing reference worker")
	if result.error.is_empty():
		check(result.records[0].uuid=="nonbuilding_first" and result.records[1].uuid=="building_second" and result.prefab_cpu.size()==1,"full chunk preserves order and deduplicates one SHA")
		var prepared:Dictionary=result.prefab_cpu[value.sha256]
		check(prepared.collision_faces[0].size()==(0 if old_shadow_control else 240000) and prepared.collision_faces[1].size()==3 and prepared.collision_faces[2].is_empty(),"later building consumer adds render demand without auxiliary expansion")
	check(FileAccess.get_sha256(fixture_file.path)==before,"full reference preparation preserves package bytes")
	check(Prepare.prepare(index,requests,fixture_file.path,helper.content_root,Cancelled.new(),null,{}, {},0,true).cancelled,"cancelled reference transaction publishes no targeted faces")
	print("SHADOW167_REFERENCE_ARTIFACT ",helper.folder)
	helper.free()


func run()->void:
	old_shadow_control="--without-shadow-face-preparation" in OS.get_cmdline_user_args()
	House.shadow_face_preparation_enabled=not old_shadow_control
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	preload("res://scripts/world3d/prefab_binary_cache.gd").enabled=false
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	controls.enable_white_materials();controls.discard_map_textures=true
	var data:=fixture();var small:Dictionary=data.meshes[0].duplicate(true)
	var indices:=PackedInt32Array();indices.resize(120000)
	for i:int in indices.size():indices[i]=i%3
	data.meshes[0].surfaces[0][Mesh.ARRAY_INDEX]=indices
	data.meshes[0].surfaces.append(data.meshes[0].surfaces[0].duplicate(true))
	data.meshes[0].materials.append(0)
	data.meshes.append(small);data.meshes.append(data.meshes[0].duplicate(true))
	data.entries[0][1]=[0,1]
	var value:=encode(data);var source:=record(value);source.building={"id":"shadow_fixture","floor":0}
	var baseline:=House.prepare_cpu(source,{},true,false)
	var partial:Dictionary=House._decoded[value.sha256]
	check(baseline.collision_faces[0].is_empty() and baseline.collision_faces[1].size()==3 and baseline.collision_faces[2].is_empty(),"collider-only demand preserves skipped render and auxiliary work")
	var main_tid:=OS.get_thread_caller_id();var worker:=Thread.new()
	worker.start(func():return {"tid":OS.get_thread_caller_id(),"prepared":House.prepare_cpu(source,{},true,true)})
	var result:Dictionary=worker.wait_to_finish();var prepared:Dictionary=result.prepared
	check(result.tid!=main_tid,"targeted face preparation runs on reference-style worker")
	check(prepared.collision_faces[0].size()==(0 if old_shadow_control else 240000) and prepared.collision_faces[1].size()==3 and prepared.collision_faces[2].is_empty(),"shadow request adds exactly render slot; auxiliary slot remains lazy")
	check(prepared.face_work.prepared_slots==(1 if old_shadow_control else 2) and prepared.face_work.skipped_slots==(2 if old_shadow_control else 1) and prepared.face_work.prepared_vertices==(3 if old_shadow_control else 240003),"work counters charge only actual requested vertices")
	check(partial.collision_faces[0].is_empty() and is_same(partial.data,House._decoded[value.sha256].data),"upgrade retains old snapshot and decoded owner")
	check(House._decoded_bytes==value.length+(3 if old_shadow_control else 240003)*12+3*16,"new face storage is charged once to existing bounded decode cache")
	var expected:=preload("res://scripts/world3d/prefab_face_arrays.gd").build(data.meshes[0])
	check(prepared.collision_faces[0].is_empty() if old_shadow_control else prepared.collision_faces[0]==expected,"triangle positions, order and winding match original expansion exactly")
	check(House.publish_prepared(source,prepared),"prepared packet publishes using existing source identity gate")
	var owner:Mesh=House.geometry(source).mesh
	check(owner._collision_faces.is_empty() if old_shadow_control else owner._collision_faces==expected,"same-code control exposes exactly the old missing render faces")
	check(owner.collision_faces()==expected,"main consumer preserves exact faces in both paths")
	var visual:=House.visual(source,false)
	check(visual.get_meta("collision_solid")==House.geometry(source).source and visual.get_meta("collision_solid").collision_faces().size()==3,"shadow preparation never replaces authored collider")
	visual.free()
	# The same geometry under another definition must use the surviving canonical
	# render owner, not a temporary owner discarded during publication.
	var variant:=data.duplicate(true);variant.entries[0][0]=["alias"]
	var variant_value:=encode(variant);var alias_record:=record(variant_value,"alias");alias_record.building=source.building
	check(House.publish_prepared(alias_record,House.prepare_cpu(alias_record,{},true,true)) and House.geometry(alias_record).mesh==owner,"prepared faces survive same-geometry material-owner alias reuse")
	var independent:=House.prepare_cpu(source,{},true,true)
	independent.collision_faces[1][0]=Vector3(99,99,99)
	check(House.prepare_cpu(source,{},true,true).collision_faces[1][0]!=Vector3(99,99,99) and owner._collision_faces==expected,"job writes cannot alter cache or published owner")
	var unique:=data.duplicate(true);unique.materials.append({"values":{"cull_mode":BaseMaterial3D.CULL_FRONT}});unique.meshes[0].materials=[0,1]
	check(ShadowDemand.white_render_slot(unique)==-1,"one surface per cull partition adds no shadow work")
	unique.meshes[0].surfaces.append(unique.meshes[0].surfaces[0]);unique.meshes[0].materials.append(0)
	check(ShadowDemand.white_render_slot(unique)==0,"repeated cull partition qualifies without flattening other culls")
	# Concurrency: source-only, targeted shadow and generic full must each get
	# their own complete request even when another mode wins the decode flight.
	House.evict_geometry({value.sha256:true,variant_value.sha256:true});evict(value.sha256)
	var start:=Semaphore.new();var ready:=Semaphore.new();var workers:Array=[]
	for mode:int in 3:
		var thread:=Thread.new();var chosen:=mode
		thread.start(func():ready.post();start.wait();return House.prepare_cpu(source,{},chosen!=2,chosen==1));workers.append(thread)
	for thread in workers:ready.wait()
	for thread in workers:start.post()
	for mode:int in workers.size():
		var packet:Dictionary=workers[mode].wait_to_finish()
		check(packet.collision_faces[0].size()==(0 if mode==0 or (mode==1 and old_shadow_control) else 240000) and packet.collision_faces[1].size()==3 and packet.collision_faces[2].size()==(240000 if mode==2 else 0),"concurrent mode gets exactly requested slots "+str(mode))
	var trials:Array=[]
	for targeted:bool in [false,true,true,false]:
		House.evict_geometry({value.sha256:true});evict(value.sha256)
		var task:=Thread.new();var worker_began:=Time.get_ticks_usec()
		task.start(func():return House.prepare_cpu(source,{},true,targeted))
		var packet:Dictionary=task.wait_to_finish();var worker_wall:=Time.get_ticks_usec()-worker_began
		House.publish_prepared(source,packet);var mesh:Mesh=House.geometry(source).mesh
		var had_faces:bool=not mesh._collision_faces.is_empty();var began:=Time.get_ticks_usec();var triangles:PackedVector3Array=mesh.collision_faces();var main_us:=Time.get_ticks_usec()-began
		check(triangles==expected and had_faces==(targeted and not old_shadow_control),"ABBA preserves geometry and exposes old main-thread expansion")
		trials.append({"targeted":targeted,"active":targeted and not old_shadow_control,"worker_wall_us":worker_wall,"main_face_us":main_us,"main_face_vertices_built":0 if had_faces else triangles.size(),"prepared_work":packet.face_work})
	# Shared source/render and BoxMesh consumers must not allocate an extra soup.
	var same:=data.duplicate(true);same.entries[0][1]=[0,0];var same_value:=encode(same)
	var same_packet:=House.prepare_cpu(record(same_value),{},true,true)
	check(same_packet.face_work.prepared_slots==1 and same_packet.collision_faces[0]==expected and same_packet.collision_faces[1].is_empty() and same_packet.collision_faces[2].is_empty(),"shared source/render slot is prepared once")
	var box_data:=data.duplicate(true);box_data.meshes[0].box_size=Vector3.ONE
	var box_value:=encode(box_data);var box_packet:=House.prepare_cpu(record(box_value),{},true,true)
	check(ShadowDemand.white_render_slot(box_data)==-1 and box_packet.collision_faces[0].is_empty() and box_packet.collision_faces[1].size()==3,"primitive box never receives a render-shadow demand")
	var changed:=data.duplicate(true);changed.meshes[0].surfaces[0][Mesh.ARRAY_VERTEX][0]=Vector3(3,2,1)
	var changed_value:=encode(changed);var changed_record:=record(changed_value,"changed")
	check(changed_value.sha256!=value.sha256 and not House.publish_prepared(changed_record,prepared),"changed source SHA rejects previous worker packet")
	var changed_packet:=House.prepare_cpu(changed_record,{},true,true)
	check(changed_packet.geometry_keys[0]!=prepared.geometry_keys[0] and House.publish_prepared(changed_record,changed_packet),"new source publishes its own geometry identity")
	House.evict_geometry({same_value.sha256:true,box_value.sha256:true,changed_value.sha256:true})
	full_reference_contract(value)
	# Re-establish canonical prepared owner after full-reference cold case.
	House.publish_prepared(source,House.prepare_cpu(source,{},true,true))
	if "--gpu-contract" in OS.get_cmdline_user_args():
		var stats_before:=Shadow.stats()
		var node:=House.visual(source,true);root.add_child(node)
		check(Shadow.attach(node),"actual opaque shadow attaches from prepared owner")
		var stats_after:=Shadow.stats()
		check(stats_after.builds==stats_before.builds+1 and stats_after.builds_prepared==stats_before.builds_prepared+(0 if old_shadow_control else 1) and stats_after.builds_unprepared==stats_before.builds_unprepared+(1 if old_shadow_control else 0) and stats_after.face_vertices_built_on_main==stats_before.face_vertices_built_on_main+(240000 if old_shadow_control else 0),"actual attach scalar counters prove coverage without trace duration threshold")
		var proxy:MeshInstance3D=node.get_meta("building_shadow_proxy")
		check(proxy.mesh.get_faces()==expected and node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and proxy.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,"proxy retains exact triangle soup and visible shadow ownership")
		node.hide();check(not proxy.is_visible_in_tree(),"cutaway visibility still propagates")
		node.free()
		var rejected:=House.visual(source,true);root.add_child(rejected)
		var transparent:=StandardMaterial3D.new();transparent.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		rejected.material_override=transparent
		check(not Shadow.attach(rejected) and rejected.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON and rejected.get_child_count()==0,"unsupported effective material rejects proxy and preserves original shadow")
		rejected.free()
		var primitive:=MeshInstance3D.new();primitive.mesh=BoxMesh.new();primitive.set_meta("ground_batch_record",source)
		check(not Shadow.attach(primitive) and primitive.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"actual box attach preserves original shadow")
		primitive.free()
	House.evict_geometry({value.sha256:true,variant_value.sha256:true})
	check(House._decoding.is_empty(),"all coalesced flights finish")
	print("SHADOW167_TARGETED_FACES ",JSON.stringify({"failures":failures,"checks":checks,"diagnostic_old":old_shadow_control,"work_red":old_shadow_control and trials.filter(func(t):return t.targeted).all(func(t):return t.main_face_vertices_built==240000),"work_green":not old_shadow_control and trials.filter(func(t):return t.targeted).all(func(t):return t.main_face_vertices_built==0),"trials":trials,"gpu_contract":"--gpu-contract" in OS.get_cmdline_user_args()}))
	quit(1 if failures else 0)
