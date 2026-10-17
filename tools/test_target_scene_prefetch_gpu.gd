extends SceneTree
const CpuService=preload("res://scripts/world3d/cross_map_prefetch.gd")
const GpuService=preload("res://scripts/world3d/target_scene_prefetch.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/runtime_completion_20261017/"
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func cpu_ready(service:Node)->bool:
	var until:=Time.get_ticks_msec()+30000
	while service._packet==null and Time.get_ticks_msec()<until:await process_frame
	return service._packet!=null
func gpu_ready(service:Node)->bool:
	var until:=Time.get_ticks_msec()+60000
	while not service._gpu_ready and Time.get_ticks_msec()<until:service._touched=Time.get_ticks_msec();await process_frame
	return service._gpu_ready
func run()->void:
	create_timer(150).timeout.connect(func():quit(2));DirAccess.make_dir_recursive_absolute(OUT)
	var dir:=Paths.cache_directory("gpu_target_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(dir)
	var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.25,0),Vector3(64,.5,64))
	var asset:=dir.path_join("textured.glb")
	check(preload("res://tools/test_asset_residency_gpu.gd").textured_fixture(asset)==OK,"create bounded real textured GLB target dependency")
	var source:Node3D=Assets.instantiate(asset);var source_owner:int=Assets._scenes[asset].get_instance_id();var asset_bytes:=FileAccess.get_file_as_bytes(asset)
	doc.add_asset({"asset_path":asset},Vector3(-4,.5,-4))
	for i in 16:doc.add_box("block",Vector3((i%4)*5,1,(i/4)*5),Vector3(2,2,2))
	var path:=dir.path_join("map.gltf");check(doc.save(path)==OK,"save isolated native target")
	var original:=FileAccess.get_file_as_bytes(path);var at:=Vector3(-4,.9,-4)
	var ledger:=Admission.new();ledger.byte_limit=GpuService.LEASE_BYTES*2
	var cpu:=CpuService.new();root.add_child(cpu);var gpu:=GpuService.new();root.add_child(gpu)
	check(cpu.request(path,at,ledger) and await cpu_ready(cpu),"prepare verified CPU target and complete GPU envelope")
	check(not cpu._packet.scene_plan.is_empty(),"GPU plan covers current source and selected rmres identities")
	check(gpu.request(path,at,ledger,cpu),"private target loader acquires shared source lease")
	check(ledger.active_workers()==2 and ledger.reserved_bytes==GpuService.LEASE_BYTES,"target coordinator and one nested worker share two admitted source slots")
	check(await gpu_ready(gpu),"target GPU buffers/materials draw in private warmup viewport")
	var count:int=gpu._scene.get_meta("stream_library",[]).size()
	check(count>0 and gpu._warm.size()>=count and ledger.active_workers()==0 and ledger.reserved_bytes==GpuService.LEASE_BYTES,"ready GPU result retains resource charge after workers join")
	var textured:=false
	for mesh:Mesh in gpu._warm:
		for slot in mesh.get_surface_count():
			var material:Material=mesh.surface_get_material(slot)
			if material is BaseMaterial3D and material.albedo_texture!=null:textured=true
	check(textured,"real imported target material and texture are uploaded and privately drawn")
	check(Assets._scenes[asset].get_instance_id()==source_owner and is_instance_valid(source),"private target preparation preserves the active source scene cache owner")
	var ids:Array=[]
	for mesh:Mesh in gpu._warm:ids.append(mesh.get_rid())
	var scene:Node=gpu.take(path,at)
	check(scene!=null and scene.get_meta("gpu_preload_hit",false) and not scene.is_inside_tree(),"single-use scene handoff preserves off-tree target ownership")
	check(ledger.reserved_bytes==0 and scene.get_meta("prefetched_gpu_owners",[]).size()>=count,"handoff transfers the exact GPU owners out of the speculative lease")
	var reused:=true
	for spec:Dictionary in scene.get_meta("stream_library",[]):
		var mesh:Mesh=spec.mesh.restore() if spec.mesh is Cpu else spec.mesh
		reused=reused and mesh.get_rid() in ids
	check(reused,"confirmed target reuses the same uploaded buffer RIDs")
	scene.free();scene=null
	check(cpu.request(path,at,ledger) and await cpu_ready(cpu) and gpu.request(path,at,ledger,cpu) and await gpu_ready(gpu),"second target is independently prepared")
	var file:=FileAccess.open(path,FileAccess.READ_WRITE);file.seek_end();file.store_string(" ");file.close()
	check(gpu.take(path,at)==null,"changed target bytes reject stale GPU scene without activation")
	await gpu.drain();check(ledger.reserved_bytes==0,"stale GPU scene and workers retire before byte release")
	file=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(original);file.close()
	check(cpu.request(path,at,ledger) and await cpu_ready(cpu) and gpu.request(path,at,ledger,cpu) and await gpu_ready(gpu),"prepare independently verified model dependency")
	file=FileAccess.open(asset,FileAccess.READ_WRITE);file.seek_end();file.store_8(0);file.close()
	check(gpu.take(path,at)==null,"changed external model bytes reject stale target GPU resources")
	await gpu.drain();file=FileAccess.open(asset,FileAccess.WRITE);file.store_buffer(asset_bytes);file.close()
	check(cpu.request(path,at,ledger) and await cpu_ready(cpu) and gpu.request(path,at,ledger,cpu),"start cancellation with an actual private loader")
	check(not ledger.reserve("required",{"estimated_bytes":1,"exclusive":true}),"source critical task preempts speculative target")
	await gpu.drain();check(ledger.reserved_bytes==0,"cancel joins workers and drops GPU results before release")
	check(FileAccess.get_file_as_bytes(path)==original,"warmup never writes authored map contents")
	check(cpu.request(path,at,ledger) and await cpu_ready(cpu) and gpu.request(path,at,ledger,cpu),"start real target worker before owner exit")
	var observed:Dictionary=gpu.profile.duplicate();gpu.free()
	check(ledger.reserved_bytes==0 and ledger.active_workers()==0,"owner exit joins private preparation and releases its full lease")
	check(GpuService.plan([{"house_prefab":{"length":GpuService.LEASE_BYTES}}],Paths.external_root(),path,FileAccess.get_sha256(path),{}).is_empty(),"oversize target declines speculation without changing author eligibility")
	var report:={"checks":checks,"failures":failures,"profile":observed,"source_worker_peak":ledger.peak_workers,"source_sha256":FileAccess.get_sha256(path)}
	source.free();Assets.evict_cached_scene(asset);cpu.free()
	FileAccess.open(OUT+"target_gpu.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("TARGET_GPU ",JSON.stringify(report));quit(1 if failures else 0)
