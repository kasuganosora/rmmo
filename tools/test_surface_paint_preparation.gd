extends SceneTree
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Prep=preload("res://scripts/world3d/surface_paint_preparation.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
const Fixture=preload("res://tools/test_native_road_preparation.gd")
var failures:=0
var checks:=0
var normal_path:=""
class Token extends RefCounted:
	var remaining:=1
	func is_cancelled()->bool:remaining-=1;return remaining<=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func bytes(mesh:Mesh)->PackedByteArray:
	var surfaces:Array=[]
	for slot:int in mesh.get_surface_count():surfaces.append(mesh.surface_get_arrays(slot))
	return var_to_bytes(surfaces)
func compare(a:Mesh,b:Mesh,label:String)->void:
	check(bytes(a)==bytes(b),label+" exact surface order/indices/positions/normals/UV/tangent channels")
	check(a.get_surface_count()==b.get_surface_count(),label+" surface count")
	for slot:int in mini(a.get_surface_count(),b.get_surface_count()):check(a.surface_get_material(slot)==b.surface_get_material(slot),label+" actual canonical material owner")
	check(a.get_aabb().is_equal_approx(b.get_aabb()),label+" output bounds")
func scenario(mapping:String,partial:bool,shared:bool,normal:bool,kerbs:int)->void:
	var fixture:=Fixture.new();var record:=fixture.road();record.road_mesh.grade=[.025,-.015]
	record.road_mesh.polygons=[[[ -.48,-.4],[-.2,-.4],[-.2,.4],[-.48,.4]],[[-.1,-.4],[.1,-.4],[.1,.4],[-.1,.4]],[[.2,-.4],[.48,-.4],[.48,.4],[.2,.4]]]
	record.road_mesh.kerbs=[]
	for i:int in kerbs:record.road_mesh.kerbs.append(fixture.part(i%2==0,i%3==0))
	var arrays:Array=Road.arrays(record);fixture.free()
	# A second disjoint pavement patch produces several independently painted faces.
	var source_bytes:=var_to_bytes(arrays)
	var material:=StandardMaterial3D.new();var slots:Array=[]
	for i:int in arrays.size():slots.append(material if shared or i<3 else StandardMaterial3D.new())
	var node:=MeshInstance3D.new();var cpu:=Cpu.from_surfaces(arrays,slots)
	node.set_meta("paint_source",cpu);node.set_meta("paint_source_materials",slots)
	var topology:=Paint.geometry(node);var pure:=Paint.geometry_arrays(arrays)
	check(var_to_bytes(topology)==var_to_bytes(pure),"pure topology equals node adapter")
	var entries:Array=[]
	for slot:int in (2 if partial else 1):
		var face_index:=0
		for face:Variant in topology.surfaces[slot].faces:
			face_index+=1
			if partial and face_index%2==0:continue
			var definition:={"name":"test","color":[1,.7,.5,1],"roughness":.7,"tile_size":[.5,2.]}
			if partial and face_index>1:definition.roughness=.4
			if normal:definition.normal_path=normal_path
			entries.append({"mesh":".","surface":slot,"face":face,"geometry":topology.surfaces[slot].signature,"mapping":mapping,"scale":[.75,1.25],"offset":[.1,-.3],"rotation":31.,"material":definition})
	var input:=var_to_bytes(entries)
	node.remove_meta("paint_geometry") # Authoring the fixture must not prepay baseline topology.
	var label:="%s partial=%s shared=%s normal=%s kerbs=%d"%[mapping,partial,shared,normal,kerbs]
	var baseline_started:=Time.get_ticks_usec()
	var old:Dictionary=Paint.painted_mesh(node,entries,true,{},true)
	var old_us:=Time.get_ticks_usec()-baseline_started
	check(old.ok,label+" baseline succeeds")
	if not old.ok:print("BASELINE_ERROR ",old)
	var main_packet:=Prep.prepare(arrays,entries)
	var worker:=Thread.new();worker.start(Prep.prepare.bind(arrays,entries))
	var packet:Dictionary=worker.wait_to_finish()
	check(packet.get("ok",false),label+" worker CPU preparation succeeds")
	check(var_to_bytes(main_packet.get("fragments"))==var_to_bytes(packet.get("fragments")),label+" serial and worker pure kernels produce identical fragments")
	if mapping=="uv" and partial and not normal:
		var workers:Array[Thread]=[]
		for i:int in 2:
			var parallel:=Thread.new();parallel.start(Prep.prepare.bind(arrays,entries));workers.append(parallel)
		for parallel:Thread in workers:
			var independent:Dictionary=parallel.wait_to_finish()
			check(var_to_bytes(independent.get("fragments"))==var_to_bytes(packet.get("fragments")),"parallel readers produce identical private fragments from shared input")
	if old.ok and packet.get("ok",false):
		var began:=Time.get_ticks_usec();var result:=Paint.painted_mesh(node,entries,true,{},true,packet);var publish_us:=Time.get_ticks_usec()-began
		check(result.get("prepared_paint",false),label+" consumes worker packet")
		if result.ok:compare(old.mesh,result.mesh,label)
		print("PAINT_PREPARE ",JSON.stringify({"case":label,"old_main_us":old_us,"same_kernel_on_main_us":main_packet.elapsed_us,"worker_us":packet.elapsed_us,"new_main_us":publish_us,"output_bytes":packet.output_bytes,"fragments":packet.fragments.size()}))
		for boundary:int in [1,2,5]:
			var token:=Token.new();token.remaining=boundary
			check(Prep.prepare(arrays,entries,token).is_empty(),label+" cancellation discards private fragments")
		var changed:=entries.duplicate(true);changed[0].offset=[.4,.4]
		check(Prep.publish(node,changed,packet,{}).is_empty(),label+" changed paint cannot borrow packet")
		var replacement:=arrays.duplicate();var alternate:=Cpu.from_surfaces(replacement,slots);node.set_meta("paint_source",alternate)
		check(Prep.publish(node,entries,packet,{}).is_empty(),label+" replaced array owner cannot borrow packet")
	check(var_to_bytes(arrays)==source_bytes and var_to_bytes(entries)==input,label+" worker never modifies borrowed input")
	node.free()
func production_handoff()->void:
	var fixture:=Fixture.new();var record:=fixture.road();record.color=[.8,.7,.6,1.]
	record.road_mesh.kerbs=[fixture.part(true,true)]
	var arrays:Array=Road.arrays(record);var geo:=Paint.geometry_arrays(arrays,false,true)
	record.surface_paint=[]
	for face:Variant in geo.surfaces[0].faces:
		record.surface_paint.append({"mesh":".","surface":0,"face":face,"geometry":geo.surfaces[0].signature,"mapping":"uv","scale":[.5,.75],"offset":[0.,0.],"rotation":0.,"material":{"name":"paint","color":[.6,.5,.4,1.],"roughness":.8}})
	var files:=preload("res://tools/test_map_dependency_index.gd").new()
	files.content_root=preload("res://scripts/world3d/map_paths.gd").external_root()
	files.folder=preload("res://scripts/world3d/map_paths.gd").cache_directory("paint_handoff_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	var f:Dictionary=files.fixture("road",[record])
	var index:Dictionary=preload("res://scripts/world3d/map_dependency_index.gd").build(f.path,files.content_root,[record])
	check(index.ok,"painted road fixture saves and indexes")
	if not index.ok:fixture.free();files.free();return
	var requests:Array=fixture.entry(index)
	var queue:=preload("res://scripts/world3d/deferred_asset_loader.gd").new()
	var doc:=preload("res://scripts/world3d/world_document.gd").new();doc.load_immutable_records=true
	queue._doc=doc;queue._reference_index=index;queue._reference_root=files.content_root
	var estimate:Dictionary=queue._estimate_job({"native_reference":true},requests)
	check(estimate.road_paint_workspace_bytes>=int(index.rows[0].memory_bytes),"paint scratch and retained fragments are included in native admission")
	check(queue._admission.reserve("fixture",estimate),"same job lease admits geometry and paint")
	var worker:=Thread.new()
	worker.start(preload("res://scripts/world3d/chunk_reference_preparation.gd").prepare.bind(index,requests,f.path,files.content_root,null,null,{}, {},0,true,{},false,estimate.road_paint_workspace_bytes))
	var packet:Dictionary=worker.wait_to_finish()
	check(packet.error.is_empty() and packet.get("surface_paints",{}).size()==1,"real chunk worker returns one prepared painted road")
	if packet.error.is_empty():
		check(packet.read_profile.reused_paint_source_bounds==1 and packet.read_profile.scanned_surface_bounds==0 and packet.read_profile.road_paint_bounds_scans==1,"chunk shares one road scan for original and painted bounds")
		check(packet.surface_bounds[record.uuid]==packet.surface_paints[record.uuid].bounds,"publication and raw source consume the same proven extent")
		queue._accept_prepared_records(packet)
		var before:=Prep.publications;var node:=doc._mesh(record)
		check(Prep.publications==before+1 and not node.has_meta("paint_error"),"WorldDocument consumes exact worker paint generation")
		var output:=bytes(node.mesh)
		var token:=preload("res://scripts/world3d/asset_worker_drainer.gd").CancelToken.new()
		queue._jobs.fixture={"token":token,"result":packet};queue._discard_job("fixture")
		check(doc.load_surface_paints.is_empty() and doc.load_surface_arrays.is_empty() and queue._admission.reserved_bytes==0,"discard clears document borrow and releases the single byte lease")
		check(bytes(node.mesh)==output,"published geometry survives private packet disposal")
		node.free()
	queue.free();fixture.free()
	for path:String in files.created:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(files.folder.path_join("road.gltf.resources"));DirAccess.remove_absolute(files.folder);files.free()
func run()->void:
	check(not Prep.enabled and not Prep.active(),"unaccepted candidate stays disabled in ordinary runtime")
	Prep.enabled=true
	check(Prep.active(),"isolated fixture explicitly enables the preparation candidate")
	# Tiny external fixture; never enters the project importer or user map.
	var image:=Image.create(2,2,false,Image.FORMAT_RGB8);image.fill(Color(.5,.5,1))
	normal_path=preload("res://scripts/world3d/map_paths.gd").external_root().path_join("cache/paint_preparation_%d/normal.png"%OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(normal_path.get_base_dir())
	check(image.save_png(normal_path)==OK,"normal fixture saved outside project")
	Paint.prepared_images={Paint.texture_key(normal_path,false,true):image}
	for mapping:String in ["uv","planar","meters"]:
		scenario(mapping,false,false,false,128)
		scenario(mapping,true,true,false,128)
	scenario("uv",true,false,true,128)
	scenario("uv",false,false,false,2048)
	production_handoff()
	Paint.prepared_images={}
	DirAccess.remove_absolute(normal_path);DirAccess.remove_absolute(normal_path.get_base_dir())
	print("SURFACE_PAINT_PREPARATION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
