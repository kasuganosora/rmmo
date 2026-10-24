extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Bounds=preload("res://scripts/world3d/procedural_surface_bounds.gd")
const Upload=preload("res://scripts/world3d/prepared_cpu_upload.gd")
const Fixture=preload("res://tools/test_native_road_preparation.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var f:=Fixture.new();var record:=f.road();record.road_mesh.kerbs=[]
	for i:int in 2048:record.road_mesh.kerbs.append(f.part(i%2==0,i%3==0))
	var arrays:=Road.arrays(record);var bytes:=var_to_bytes(arrays);var bounds:=Bounds.bounds(arrays)
	var materials:Array=[]
	for i:int in arrays.size():var m:=StandardMaterial3D.new();m.albedo_color=Color(.1*i,.2,.3);materials.append(m)
	var rows:Array=[]
	for prepared:bool in ([true,false,false,true] if OS.get_cmdline_user_args().has("--prepared-first") else [false,true,true,false]):
		var cpu:Mesh=Bounds.make_cpu(arrays,materials,bounds);var began:=Time.get_ticks_usec();var worker_us:=0
		if prepared:
			var thread:=Thread.new();thread.start(Upload.prepare.bind(arrays,16*1024*1024));var packed=thread.wait_to_finish();worker_us=Time.get_ticks_usec()-began
			check(packed!=null and packed.surfaces.size()==arrays.size(),"complete worker packet without mesh resources")
			Upload.attach(cpu,packed)
		began=Time.get_ticks_usec();var mesh:Mesh=Upload.restore(cpu) if prepared else cpu.restore();var install_us:=Time.get_ticks_usec()-began
		rows.append({"prepared":prepared,"main_install_us":install_us,"worker_us":worker_us})
		# Native tangent/normal packing is lossy even in the ordinary upload.
		var control:Mesh=Cpu.from_surfaces(arrays,materials).restore()
		for slot:int in arrays.size():
			check(var_to_bytes(RenderingServer.mesh_get_surface(mesh.get_rid(),slot))==var_to_bytes(RenderingServer.mesh_get_surface(control.get_rid(),slot)),"native surface bytes equal ordinary upload")
		check(mesh.get_aabb()==control.get_aabb(),"native bounds equal ordinary upload")
		check(Upload.restore(cpu)==mesh,"repeated instance reuses installed GPU resource")
		var variant:Mesh=Bounds.make_cpu(arrays,materials,bounds);variant.source_reference=cpu.source_reference;variant.materials[0]=StandardMaterial3D.new()
		var variant_mesh:Mesh=Upload.restore(variant)
		check(variant_mesh!=mesh and variant_mesh.surface_get_material(0)==variant.materials[0] and mesh.surface_get_material(0)==materials[0],"material variant stays independent")
		mesh.surface_set_material(0,StandardMaterial3D.new())
		check(Upload.restore(cpu)!=mesh,"changed original invalidates shared generation")
		check(var_to_bytes(arrays)==bytes,"borrowed geometry is unchanged")
		await process_frame
	var borrowed:Array=Upload.prepare(arrays,16*1024*1024).surfaces;var borrowed_bytes:=var_to_bytes(borrowed)
	var packet:=Upload.Payload.new();packet.surfaces=borrowed;packet.bytes=16*1024*1024;packet=null
	for i:int in 12:await process_frame
	check(var_to_bytes(borrowed)==borrowed_bytes,"retired payload never mutates the borrowed outer surface array")
	check(Upload.prepare(arrays,1)==null,"packing exceeding the caller output allowance falls back")
	check(Upload.prepare(arrays,Upload.MAX_BYTES+1)==null,"oversized jobs never bypass the bounded packing allowance")
	var budget:=preload("res://scripts/world3d/native_road_preparation.gd").estimate(record)
	var thread:=Thread.new();thread.start(preload("res://scripts/world3d/native_road_preparation.gd").prepare.bind(record,null,false,"",budget,"",true))
	var road:Dictionary=thread.wait_to_finish()
	check(road.upload!=null and road.upload.bytes<=budget.output_bytes and road.estimated_bytes==budget.estimated_bytes,"real road worker retains packed bytes inside the original second output reservation")
	var native_packet_bytes:=var_to_bytes(road.upload.surfaces)
	var owner:Mesh=Bounds.make_cpu(road.arrays,materials,Bounds.bounds(road.arrays));Upload.attach(owner,road.upload)
	var projection:Mesh=Bounds.make_cpu(road.arrays,materials,owner.bounds);projection.materials[0]=StandardMaterial3D.new();Upload.inherit(owner,projection)
	check(Upload.restore(projection).surface_get_material(0)==projection.materials[0] and owner.source_reference==null,"private material projection shares CPU packing without changing the owner")
	var stream=preload("res://scripts/world3d/world_stream.gd")
	var visual:MeshInstance3D=stream._spawn({"uuid":"packed_road","mesh":owner,"surface_overrides":[]})
	check(visual.mesh is ArrayMesh and visual.mesh.get_surface_count()==arrays.size() and not owner.has_meta(Upload.META),"stream spawn consumes the prepared upload exactly once")
	check(var_to_bytes(road.upload.surfaces)==native_packet_bytes,"two independent material installations never mutate or consume shared native buffers")
	visual.free()
	var indexed:Array=preload("res://tools/stress_mesh_surface_preparation.gd").surface(24000)
	var levels:Array=[{8.:PackedInt32Array([0,1,2,3,4,5])}]
	var indexed_cpu:Mesh=Bounds.make_cpu([indexed],[null],Bounds.bounds([indexed]));indexed_cpu.lods=levels
	var lod_thread:=Thread.new();lod_thread.start(Upload.prepare.bind([indexed],16*1024*1024,levels))
	var lod_packet=lod_thread.wait_to_finish();Upload.attach(indexed_cpu,lod_packet)
	var indexed_mesh:Mesh=Upload.restore(indexed_cpu)
	var control_cpu:Mesh=Bounds.make_cpu([indexed],[null],indexed_cpu.bounds);control_cpu.lods=levels
	var control_mesh:Mesh=control_cpu.restore()
	check(indexed_mesh.get("_surfaces")==control_mesh.get("_surfaces"),"indexed geometry and LOD index tables preserve exact native bytes")
	var cancelled:Dictionary={"surface_uploads":{"road":road.upload}}
	var retained_bytes:=var_to_bytes(road.upload.surfaces)
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(cancelled)
	check(cancelled.is_empty() and retained_bytes==var_to_bytes(road.upload.surfaces),"cancelled handoff drops its owner without clearing another packet borrower")
	var queue:=preload("res://scripts/world3d/deferred_asset_loader.gd").new()
	var doc:=preload("res://scripts/world3d/world_document.gd").new();queue._doc=doc
	doc.load_box_meshes={};doc.load_material_pool={}
	queue._accept_prepared_records({"surface_arrays":{"road":arrays},"surface_bounds":{"road":bounds},"surface_uploads":{"road":road.upload}})
	var fresh:Array=Road.arrays(f.road())
	queue._accept_prepared_records({"surface_arrays":{"road":fresh}})
	check(is_same(doc.load_surface_arrays.road,fresh) and not doc.load_surface_uploads.has("road") and not doc.load_surface_bounds.has("road"),"same UUID without optional products revokes old upload and bounds with old geometry")
	queue._accept_prepared_records({"surface_arrays":{"road":arrays},"surface_bounds":{"road":bounds},"surface_uploads":{"road":road.upload}})
	var residency:=preload("res://scripts/world3d/native_residency.gd").new();residency._queue=queue
	residency._release_preparation_cache([{"compact_record":{"uuid":"road"}}])
	check(not doc.load_surface_arrays.has("road") and not doc.load_surface_uploads.has("road") and not doc.load_surface_bounds.has("road"),"native retirement releases all three products for the same generation")
	residency.free();queue.free()
	f.free();var report:={"failures":failures,"runs":rows,"installed_surfaces":Upload.installed_surfaces}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):var file:=FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(1 if failures else 0)
