extends SceneTree
## Reproduce production streaming which stays busy before batch reconciliation.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func membership(batches:Node)->Dictionary:
	var result:Dictionary={}
	for key:String in batches.groups:
		var names:Array=[]
		for node:Node in batches.groups[key].members:names.append(str(node.name))
		result[key]=names
	return result
func run()->void:
	Stream.progressive_white_batches_enabled=not "--baseline" in OS.get_cmdline_user_args()
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	controls.discard_map_textures=true;controls.enable_white_materials()
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(4,8,12);camera.look_at(Vector3(4,0,4));camera.current=true
	var box:=BoxMesh.new();box.size=Vector3(.3,.2,.3);box.material=controls.white_material()
	var cpu:Mesh=Cpu.capture(box);var original:=var_to_bytes(cpu.surfaces)
	var library:Array=[]
	for i:int in 785:
		var position:=Vector3((i%28)*.3,0,(i/28)*.3);var id:="source%04d"%i
		var record:Dictionary={"uuid":id,"kind":"box","surface_id":"block" if i==784 else "ground","collision":"none","size":[.3,.2,.3],"position":[position.x,0,position.z],"rotation":[0,0,0]}
		library.append({"uuid":id,"position":position,"rotation":Vector3.ZERO,"transform":Transform3D(Basis.IDENTITY,position),"chunk":Stream.chunk_key(position),"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO,"mesh":cpu,"material_override":null,"surface_overrides":[],"cast_shadow":GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"extras":{"rmmo_collision":"none","surface_id":record.surface_id},"ground_batch_record":record})
	var map:=Node3D.new();root.add_child(map);map.set_meta("stream_library",library)
	var indexed:=Index.build(library)
	for key:String in indexed:map.set_meta(key,indexed[key])
	var early_syncs:=0;var frames:=0;var deadline:=Time.get_ticks_msec()+60000
	while not map.has_meta("stream_chunk") and Time.get_ticks_msec()<deadline:
		Stream.sync(map,map,Vector3(4,0,4),Stream.FRAME_BUDGET);frames+=1
		var batches:Node=map.get_node_or_null("GroundRenderBatches")
		if batches!=null and int(map.get_meta("stream_cursor",0))<map.get_meta("stream_jobs",[]).size():early_syncs=maxi(early_syncs,batches.sync_count)
		await process_frame
	check(map.has_meta("stream_chunk"),"ordinary twelve-object streaming eventually settles")
	check(early_syncs==0 if "--baseline" in OS.get_cmdline_user_args() else early_syncs>0,"batch preparation can start before the complete residency queue drains")
	var batches:Node=map.get_node("GroundRenderBatches")
	while (not batches._preparation.is_empty() or not batches.pending.is_empty() or not batches._workers.is_empty()) and Time.get_ticks_msec()<deadline:await process_frame
	var before:=membership(batches);var sources:Dictionary=map.get_meta("stream_meshes")
	check(sources.size()==785 and batches.stats().source_objects==784,"every eligible source is batched and the ineligible singleton remains independent")
	batches.sync(sources.values());batches.flush()
	check(before==membership(batches),"progressive final groups and member order exactly match full reconciliation")
	check(batches.live_worker_joins==0 and original==var_to_bytes(cpu.surfaces),"interactive work joins no live worker and preserves author arrays")
	print("PROGRESSIVE_RUNTIME_BATCHES ",JSON.stringify({"early_syncs":early_syncs,"frames":frames,"failures":failures}))
	map.free();camera.free();await process_frame;quit(1 if failures else 0)
