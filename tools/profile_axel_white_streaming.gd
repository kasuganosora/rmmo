extends "res://tools/profile_axel_game_pipeline.gd"
## Geometry-only traversal. Uses production demands, publication, render/physics
## residency and both retirement services. Navigation retains only its ordinary
## source catalogue/retirement checks; no Recast baking, actors or HUD run here.
const Stream=preload("res://scripts/world3d/world_stream.gd")
class GeometryHost:
	extends Node3D
	var _ready_for_play:=true
	var _transfer_pending:=false
	var _navigation:Node
var traversed:=false
var position:=Vector3.ZERO
var previous_cell:=Vector2i(2147483647,2147483647)
var crossings:Array=[]
var sync_calls:Array=[]
var publication_events:Array=[]
var membership:Dictionary={}
var removed:Dictionary={}
var reloaded:Dictionary={}
var seen:Dictionary={}
var before_counts:Dictionary={}
var next_residency_sample:=0
var residency_samples:Array=[]

func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:Dictionary=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_white_streaming.gd"]=FileAccess.get_sha256("res://tools/profile_axel_white_streaming.gd")
	return result

func finish(code:int)->void:
	if not traversed and code==0 and is_instance_valid(mesh_map):
		traversed=true
		await traverse()
	await super.finish(code)

func sample_residency()->Dictionary:
	var assets:Node=mesh_map.get_node("AssetResidency")
	var native:Node=mesh_map.get_node("NativeResidency")
	var queue:Node=mesh_map.get_node("DeferredAssets")
	return {"at_ms":(Time.get_ticks_usec()-began)/1000.,"phase":phase,"position":[position.x,position.y,position.z],"specs":mesh_map.get_meta("stream_library",[]).size(),"visuals":mesh_map.get_meta("stream_meshes",{}).size(),"bodies":mesh_map.get_meta("stream_bodies",{}).size(),"asset":assets.profile.duplicate(),"native":native.profile.duplicate(),"pending":queue.pending.size(),"unpublished":queue._demanded_by_id.size(),"jobs":queue._jobs.size(),"admission":queue._admission.snapshot()}

func track_membership()->void:
	var current:Dictionary=mesh_map.get_meta("stream_by_id",{})
	for id:String in membership:
		if not current.has(id):removed[id]=true
	for id:String in current:
		if removed.has(id):reloaded[id]=true
		seen[id]=true
	membership={}
	for id:String in current:membership[id]=true

func tick_geometry()->void:
	var queue:Node=mesh_map.get_node("DeferredAssets")
	queue.prioritize(position)
	var footprint:=AABB(Vector3(position.x-2,-100000,position.z-2),Vector3(4,200000,4))
	queue.ensure_geometry(footprint,"player_collision")
	current_scene._navigation._local_clip=footprint
	var cell:=Stream.chunk_key(position)
	if cell!=previous_cell:
		crossings.append({"at_ms":(Time.get_ticks_usec()-began)/1000.,"phase":phase,"from":[previous_cell.x,previous_cell.y],"to":[cell.x,cell.y]});previous_cell=cell
	var start:=Time.get_ticks_usec()
	Stream.sync(mesh_map,current_scene,position,Stream.FRAME_BUDGET)
	var elapsed:=Time.get_ticks_usec()-start
	if elapsed>5000:sync_calls.append({"at_ms":(Time.get_ticks_usec()-began)/1000.,"phase":phase,"ms":elapsed/1000.,"cursor":mesh_map.get_meta("stream_cursor",0),"jobs":mesh_map.get_meta("stream_jobs",[]).size()})
	var camera:Camera3D=root.get_camera_3d()
	if camera!=null:camera.position=position+Vector3(0,4,7);camera.look_at(position+Vector3(0,1,0))
	if Time.get_ticks_msec()>=next_residency_sample:
		next_residency_sample=Time.get_ticks_msec()+500
		track_membership();residency_samples.append(sample_residency())

func leg(label:String,destination:Vector3,seconds:float)->void:
	phase=label;var start:=Time.get_ticks_usec();var origin:=position
	print("WHITE_TRAVERSAL ",label," from=",origin," to=",destination)
	while Time.get_ticks_usec()-start<int(seconds*1000000.):
		position=origin.lerp(destination,minf(1.,(Time.get_ticks_usec()-start)/(seconds*1000000.)))
		tick_geometry();await process_frame
	position=destination;tick_geometry();await process_frame

func settle_demands(label:String,at:Vector3,seconds:float)->void:
	phase=label;position=at
	var began:=Time.get_ticks_usec();var stable:=0
	var queue:Node=mesh_map.get_node("DeferredAssets")
	var batches:Node=mesh_map.get_node_or_null("GroundRenderBatches")
	while Time.get_ticks_usec()-began<int(seconds*1000000.) and stable<3:
		tick_geometry();await process_frame
		var ready:bool=queue._demanded_by_id.is_empty() and queue._jobs.is_empty() and mesh_map.get_meta("stream_jobs",[]).is_empty() and mesh_map.has_meta("stream_chunk")
		if batches!=null:ready=ready and batches._preparation.is_empty() and batches.pending.is_empty() and batches._workers.is_empty()
		stable=stable+1 if ready else 0
	if not report.has("demand_settling"):report.demand_settling=[]
	report.demand_settling.append({"phase":label,"extra_ms":(Time.get_ticks_usec()-began)/1000.,"settled":stable==3,"state":sample_residency()})
	check(stable==3,"all current geometry demands and batches settle: "+label)

func steady_geometry(label:String,at:Vector3)->void:
	var seconds:=0.
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--steady-seconds="):seconds=clampf(arg.trim_prefix("--steady-seconds=").to_float(),0.,60.)
	if seconds<=0:return
	var queue:Node=mesh_map.get_node("DeferredAssets")
	check(queue._demanded_by_id.is_empty() and queue._jobs.is_empty(),"steady measurement starts after all current geometry demands finish")
	var methods:=Trace.methods_enabled;Trace.methods_enabled=false
	report.traversal_contract.steady_methods=false
	await leg(label,at,seconds)
	Trace.methods_enabled=methods

func on_publication(specs:Array)->void:
	# Raw glTF material objects do not pass through the procedural material
	# factory. Normalize every later arrival too, retaining surface cull modes.
	var stage_began:=Trace.begin("probe.whiten_publication")
	for spec:Dictionary in specs:whiten_spec(spec)
	Trace.elapsed("probe.whiten_publication",stage_began,{"specs":specs.size()})
	publication_events.append({"at_ms":(Time.get_ticks_usec()-began)/1000.,"phase":phase,"count":specs.size()})
	stage_began=Trace.begin("probe.navigation_append")
	var result:Dictionary=current_scene._navigation.append_specs(specs)
	Trace.elapsed("probe.navigation_append",stage_began,{"specs":specs.size()})
	if not result.ok:report.failures.append("navigation source catalogue append: "+str(result.reason))

func traverse()->void:
	phase="white_traversal_setup"
	if "--stream-methods" in OS.get_cmdline_user_args():
		Trace.methods_enabled=true
		for label:String in ["native_residency.poll","native_residency.observe","asset_residency.poll","asset_residency.observe","world_navigation.try_retire_specs","world_stream.can_retire_specs","world_stream.retire_specs","stream_index.build","stream_index._commit_owned_retire","stream_index.validate_owned_retire","ground_batcher._drop","ground_batcher.restore","world_stream._spec","ground_cpu_mesh.restore","world_document._mesh","surface_materials.apply","surface_materials.painted_mesh"]:Trace.method_labels["method."+label]=true
		for label:String in ["deferred_asset_loader._discard_job","asset_worker_drainer.dispose_scene","asset_worker_drainer.dispose_result","asset_worker_drainer.synchronize_transfer","runtime_asset_cache_scope._release_template"]:Trace.method_labels["method."+label]=true
		for label:String in ["resource_retirement.defer_import_packet","resource_retirement._advance_import"]:Trace.method_labels["method."+label]=true
		for label:String in ["world_document._asset","world_document._namespace_asset","model_components.apply","asset_library._instantiate"]:Trace.method_labels["method."+label]=true
		for label:String in ["ground_batcher._process","ground_batcher._commit","ground_batcher._build_next","ground_batcher._prepare_step","ground_batch_geometry.upload","world_stream.sync"]:Trace.method_labels["method."+label]=true
		for label:String in ["world_stream._sync_work","world_stream._apply","world_stream._spawn","world_stream._prepare_collision","world_stream._prepare_collision_impl","world_stream._finish_loading_sources"]:Trace.method_labels["method."+label]=true
	check(mesh_only and white_material and not report.controls.map_textures,"traversal is strictly white geometry without map textures")
	if not mesh_only or not white_material or report.controls.map_textures:return
	var host:Node=current_scene;host.set_script(GeometryHost)
	var queue:Node=mesh_map.get_node("DeferredAssets")
	var nav:=preload("res://scripts/world3d/world_navigation.gd").new()
	nav.configure_streaming_geometry(func(_clip:AABB):return {"ok":true,"error":""})
	nav.map=NavigationServer3D.map_create();nav.ready_for_queries=true
	host.add_child(nav);nav.set_process(false);host._navigation=nav
	check(nav.append_specs(mesh_map.get_meta("stream_library",[])).ok,"real navigation source retirement checks retain initial geometry without baking")
	var assets:=preload("res://scripts/world3d/asset_residency.gd").new();assets.configure(host,mesh_map,queue);mesh_map.add_child(assets)
	var native:=preload("res://scripts/world3d/native_residency.gd").new();native.configure(host,mesh_map,queue);mesh_map.add_child(native)
	mesh_map.set_meta("stream_children",mesh_map.get_child_count())
	queue.published.connect(on_publication);queue.activate(host)
	# The production World3D ends its covered entry transaction here. This
	# isolated host never begins that transaction, so explicitly withdraw the
	# loader's handoff ticket once initial meshes/colliders/batches are ready.
	# Keeping it would falsely pin the spawn building throughout the far leg.
	queue.release_demand("entry_safety")
	check(not queue._demands.has("entry_safety"),"standalone white handoff withdraws the completed loader safety ticket")
	await process_frame # Attribute initial service binding to setup, not movement.
	position=Vector3(report.requested_spawn[0],report.requested_spawn[1],report.requested_spawn[2]);track_membership()
	before_counts=sample_residency()
	var origin:=position
	# Pick an actual indexed prop district 256--448 m from spawn, rather than
	# driving into an empty coordinate and claiming it exercised loading.
	var destination:=origin+Vector3(320,0,0);var candidates:Array=[]
	for row:Dictionary in queue._reference_index.rows:
		if row.classification!="spatial" or row.asset_path.is_empty() or not row.group_id.is_empty():continue
		var center:Vector3=row.bounds.get_center();center.y=origin.y
		var distance:=center.distance_to(origin)
		if distance>=256 and distance<=448:candidates.append(center)
	if not candidates.is_empty():
		candidates.sort_custom(func(a:Vector3,b:Vector3):return a.distance_squared_to(origin)>b.distance_squared_to(origin))
		destination=candidates[0]
	report.traversal_contract={"navigation":"source catalogue and real retirement preflight only; no baking/query/actors","chunk_m":Stream.CHUNK_M,"asset_grace_msec":assets.grace_msec,"native_grace_msec":native.grace_msec,"exit_margin_m":assets.exit_margin,"candidate_districts":candidates.size(),"destination":[destination.x,destination.y,destination.z],"movement":"controlled geometry focus/camera sweep, no gameplay movement claim","runtime_demands":"production prioritize + player_collision, normal radii, budgets and workers"}
	var origin_seconds:=30.
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--origin-seconds="):origin_seconds=clampf(arg.trim_prefix("--origin-seconds=").to_float(),5.,120.)
	await leg("white_stream_origin",origin,origin_seconds)
	if "--settle-demands" in OS.get_cmdline_user_args():await settle_demands("white_origin_demand_settle",origin,90.)
	await steady_geometry("white_origin_steady",origin)
	if "--origin-only" in OS.get_cmdline_user_args():
		report.origin_after=sample_residency();return
	if not "--native-only" in OS.get_cmdline_user_args():
		await leg("white_stream_outbound",destination,maxf(16.,origin.distance_to(destination)/16.))
		await leg("white_stream_unload",destination,25.)
		await leg("white_stream_return",origin,maxf(16.,origin.distance_to(destination)/16.))
		await leg("white_stream_reload",origin,25.)
		var boundary:=origin;boundary.x=(floorf(origin.x/Stream.CHUNK_M)+1.)*Stream.CHUNK_M
		for i:int in 4:await leg("white_stream_reverse_%d"%i,boundary+Vector3(-4 if i%2==0 else 4,0,0),2.)
		await leg("white_stream_reversal_settle",origin,10.)
	if "--native-departure" in OS.get_cmdline_user_args():
		var largest_id:="";var largest_ids:Array=[];var unit_sizes:Array=[]
		for id:String in native._resident:
			var ids:Array=native._resident[id].ids
			unit_sizes.append({"id":id,"specs":ids.size(),"kind":native._units[id].kind})
			if native._units[id].kind=="building" and ids.size()>largest_ids.size():largest_id=id;largest_ids=ids.duplicate()
		unit_sizes.sort_custom(func(a:Dictionary,b:Dictionary):return a.specs>b.specs)
		report.native_ownership_coverage={"largest_building":largest_id,"largest_spec_count":largest_ids.size(),"units_before_departure":unit_sizes}
		var far:=origin+Vector3(2048,0,2048)
		await leg("white_native_departure",far,24.)
		await leg("white_native_unload",far,30.)
		var extended_seconds:=0.
		# A small-unit-only result cannot validate the imported building path.
		# Record any extra drain time instead of hiding the scheduler's latency.
		while not largest_id.is_empty() and native._resident.has(largest_id) and extended_seconds<60.:
			await leg("white_native_drain_extension",far,5.);extended_seconds+=5.
		report.native_ownership_coverage.extra_drain_seconds=extended_seconds
		report.native_ownership_coverage.largest_retired=not largest_id.is_empty() and not native._resident.has(largest_id)
		if not report.native_ownership_coverage.largest_retired and native._resident.has(largest_id):
			report.native_ownership_coverage.remaining_largest={"outside_since":native._resident[largest_id].outside_since,"now_msec":Time.get_ticks_msec(),"needed":native._needed(native._units[largest_id]),"bounds":var_to_str(native._units[largest_id].bounds),"preflight":Stream.can_retire_specs(mesh_map,native._resident[largest_id].ids,true)}
		check(report.native_ownership_coverage.largest_retired,"far departure actually retires the largest resident building ownership unit")
		report.native_far_state=sample_residency()
		check(native.profile.retired_units>0,"leaving the real long render ring retires native ownership units too")
		await leg("white_native_return",origin,24.)
		await leg("white_native_reload",origin,35.)
		if "--settle-demands" in OS.get_cmdline_user_args():await settle_demands("white_return_demand_settle",origin,90.)
		await steady_geometry("white_return_steady",origin)
		check(native.profile.revisits>0,"return across the long ring reconstructs retired native UUIDs")
		var returned:Dictionary=mesh_map.get_meta("stream_by_id",{})
		var missing:Array=[]
		for id:String in largest_ids:
			if not returned.has(id):missing.append(id)
		report.native_ownership_coverage.missing_building_parts_after_return=missing
		check(not largest_ids.is_empty() and missing.is_empty(),"return restores every original part UUID of the largest retired building")
	track_membership()
	report.traversal={"before":before_counts,"after":sample_residency(),"crossings":crossings,"sync_calls_over_5ms":sync_calls,"publications":publication_events,"residency_samples":residency_samples,"unique_specs_seen":seen.size(),"removed_specs":removed.keys(),"reloaded_specs":reloaded.keys()}
	check(crossings.size()>=10,"actual focus crosses multiple 32 m cells and returns")
	check(not publication_events.is_empty(),"crossing exercises actual deferred geometry publication")
	check(not removed.is_empty(),"normal residency grace expires and removes geometry ownership")
	check(not reloaded.is_empty(),"return reloads previously retired geometry namespaces")
	check(queue.error.is_empty() and queue.instance_errors.is_empty(),"white traversal publications have no rejected geometry")
	print("WHITE_TRAVERSAL_COMPLETE crossings=",crossings.size()," removed=",removed.size()," reloaded=",reloaded.size())
	# Exit with a newly admitted ownership transaction as a separate stress
	# phase. This is an explicit focus jump, not part of the walking leg data.
	if not queue.pending.is_empty():
		var target:Vector3=queue.pending[0].bounds.get_center();target.y=origin.y
		phase="white_stream_exit_inflight";position=target
		var deadline:=Time.get_ticks_msec()+4000
		while queue._jobs.is_empty() and Time.get_ticks_msec()<deadline:
			tick_geometry();await process_frame
		report.traversal_exit_inflight={"jobs":queue._jobs.size(),"admission":queue._admission.snapshot(),"position":[position.x,position.y,position.z]}
		check(not queue._jobs.is_empty(),"map exit also exercises admitted chunk work before publication finishes")
