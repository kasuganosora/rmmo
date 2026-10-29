extends "res://tools/test_editor_native_texture_join_gpu.gd"
## Same real LoadJob/STEX/render/reuse/cancellation fixture with the experimental
## published-geometry tracker enabled only inside this test process.
const Ownership=preload("res://scripts/world_editor/prepared_model_ownership.gd")
var tracker:Node
var geometry_envelope:=67108864
var held_native:Texture2D
var previous_residency:=false

func fixture()->Node3D:
	var scene:=super.fixture()
	# Actual imported geometry is ArrayMesh. Preserve the source fixture's exact
	# arrays/materials instead of broadening the production tracker's type gate.
	for node:MeshInstance3D in scene.get_children():
		var old:PrimitiveMesh=node.mesh;var mesh:=ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,old.get_mesh_arrays())
		mesh.surface_set_material(0,old.material)
		node.mesh=mesh
	return scene

func run()->void:
	previous_residency=Job.prepared_model_residency_enabled
	check(not previous_residency,"production residency default is false before experimental GPU probe")
	Job.prepared_model_residency_enabled=true
	await super.run()

func make_job(paths:Array,pool:RefCounted=null)->Dictionary:
	var host:=Host.new();root.add_child(host)
	var job:=Job.new();job.editor=host;job._timings.build={"units":{}};host.add_child(job)
	if pool!=null:job.native_texture_pool=pool
	var records:Array=[]
	for path:String in paths:records.append({"kind":"asset","uuid":path.get_file(),"asset_path":path})
	job._begin_asset_lookahead(records)
	check(job._preparation.ledger==host._shared_preparation_ledger,"experimental publisher uses the actual editor shared admission ledger")
	check(job._preparation.resident_enabled and Job.prepared_model_residency_enabled,"experimental tracker route is actually enabled")
	tracker=job._model_ownership
	check(tracker!=null and tracker.get_script()==Ownership,"real production ownership tracker is used without subclass or stub")
	return {"host":host,"job":job,"records":records,"helper":job._native_textures}

func wait_ready(state:Dictionary)->void:
	await super.wait_ready(state)
	for record:Dictionary in state.records:
		var key:String="model:"+record.asset_path
		var queue:Node=state.job._preparation
		var packet:Dictionary=queue.rows[key].packet
		var before:Dictionary=queue.ledger.snapshot();var published:Dictionary=tracker.report()
		var receipt:Dictionary=tracker.preflight(state.job._model_candidates[record.asset_path],packet,geometry_envelope)
		check(receipt.get("ok",false),"actual registered native owner passes real tracker preflight "+record.uuid)
		if not receipt.get("ok",false):print("GPU_TRACKER_REJECT ",JSON.stringify(receipt))
		check(before==queue.ledger.snapshot() and published==tracker.report() and not packet.is_empty(),"preflight retains queue lease and mutable disposal packet "+record.uuid)

func publish_all(state:Dictionary)->Array:
	var scenes:=await super.publish_all(state)
	var label:String=state.records[0].uuid
	var expected:int=geometry_envelope*(3 if label=="inbound.glb" else 2)
	check(tracker.report().published_envelope_bytes==expected,"real publication retains the exact independent geometry envelopes "+label)
	report["tracker_after_publication_"+label]=tracker.report()
	for record:Dictionary in state.records:
		var key:String="model:"+record.asset_path
		check(state.job._preparation.rows[key].packet.is_empty() and not state.job._preparation.rows[key].has("contract"),"actual queue releases nested packet and contract after tracker adoption "+record.uuid)
	if label=="inbound.glb" and not scenes.is_empty():held_native=scenes[0].get_child(0).mesh.surface_get_material(0).albedo_texture
	return scenes

func wait_tracker_bytes(expected:int,label:String)->void:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		tracker.collect_retired(100)
		if tracker.report().published_envelope_bytes==expected:break
		await process_frame
	report["tracker_"+label]=tracker.report()
	check(tracker.report().published_envelope_bytes==expected,label+": real published geometry charge equals "+str(expected))

func close_job(state:Dictionary,label:String)->void:
	await super.close_job(state,label)
	if label=="cold":await wait_tracker_bytes(geometry_envelope*2,"old_cache_retains_geometry")
	elif label=="inbound":await wait_tracker_bytes(geometry_envelope,"old_geometry_retires_while_shared_texture_lives")
	elif label.begins_with("cancel_"):await wait_tracker_bytes(0,label+"_no_published_geometry")

func wait_engine_zero(label:String)->void:
	if label=="all_published_released":
		await wait_tracker_bytes(0,"all_geometry_retires_while_native_texture_held")
		var streaming:=Engine.get_singleton("TextureStreaming")
		report.engine_bytes_with_only_explicit_texture=int(streaming.call("get_memory_budget_bytes_used"))
		check(held_native!=null and held_native.call("is_streaming_active") and report.engine_bytes_with_only_explicit_texture>0,"independent streamed owner stays engine-accounted without retaining old geometry envelopes")
		held_native=null
	await super.wait_engine_zero(label)

func finish()->void:
	Job.prepared_model_residency_enabled=previous_residency
	check(not Job.prepared_model_residency_enabled,"experimental GPU test restores the unchanged false default")
	if tracker!=null:report.tracker_final=tracker.report()
	super.finish()
