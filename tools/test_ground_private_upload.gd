extends SceneTree
## Real layered-terrain upload, exact CPU/texture owners and first-draw parity.
## GPU validation on the private desktop; no author resources or map writes.
const Geometry=preload("res://scripts/world3d/ground_batch_geometry.gd")
const Upload=preload("res://scripts/world3d/ground_batch_private_upload.gd")
const Ground=preload("res://scripts/world3d/ground_batcher.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const River=preload("res://scripts/world3d/river_materials.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Retirement=preload("res://scripts/world3d/cpu_worker_retirement.gd")
const Presented=preload("res://scripts/util/frame_presentation.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
var checks:=0
var failures:Array=[]
var output:=""
var viewport:SubViewport
var visual:MeshInstance3D
var rows:Array=[]

class Gate extends RefCounted:
	var mutex:=Mutex.new()
	var ready:=false
	var opened:=false
	var mesh:WeakRef
	static func work(gate:Gate,members:Array)->Dictionary:
		var result:=Upload.build(members,Vector3.ZERO)
		gate.mutex.lock();gate.mesh=weakref(result.mesh);gate.ready=true;gate.mutex.unlock()
		var deadline:=Time.get_ticks_msec()+5000
		while Time.get_ticks_msec()<deadline:
			gate.mutex.lock();var done:=gate.opened;gate.mutex.unlock()
			if done:break
			OS.delay_usec(100)
		return result
	func is_ready()->bool:
		mutex.lock();var value:=ready;mutex.unlock();return value
	func open()->void:
		mutex.lock();opened=true;mutex.unlock()

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)

func members()->Array:
	var result:Array=[]
	var mask:=Image.create(3,3,false,Image.FORMAT_RGBA8);mask.fill(Color(.4,.2,0,1))
	var pixels:=Image.create(8,8,false,Image.FORMAT_RGBA8);pixels.fill(Color(.25,.7,.4))
	var texture:=ImageTexture.create_from_image(pixels)
	for i in 2:
		var record:={"uuid":"private_terrain_"+str(i),"kind":"box","surface_id":"ground","collision":"walk","position":[i*8,0,0],"rotation":[0,0,0],"size":[8,1,8],"color":[.3,.5,.2],"terrain_mesh":{"version":1,"columns":2,"rows":2,"floor":-2,"heights":[0,.3,1.,.1,.4,1.2,.2,.6,1.4],"holes":[false,false,false,false]}}
		# Equal batch keys can come from distinct live material owners. Their
		# per-source height images still differ and must reach the correct layer.
		var material:ShaderMaterial=River.terrain(record).duplicate()
		material.set_shader_parameter("base_albedo",texture);material.set_shader_parameter("base_has_albedo",true)
		var heights:=Image.create(3,3,false,Image.FORMAT_RF);heights.fill(Color(.1+.4*i,0,0))
		material.set_meta("terrain_height_image",heights)
		material.set_meta("ground_mask_image",mask)
		var arrays:=Terrain.arrays(record);var slots:Array=[];var keys:Array=[]
		for slot in arrays.size():slots.append(material);keys.append(Geometry.material_key(material))
		result.append({"record":record,"transform":Transform3D(Basis.IDENTITY,Vector3(i*8,0,0)),"surfaces":arrays,"materials":slots,"keys":keys})
	return result

func capture(mesh:Mesh)->Image:
	visual.mesh=mesh
	await Presented.drawn()
	return viewport.get_texture().get_image()

func execute(source:Array,background:bool,plain_roads:bool=false)->Dictionary:
	var began:=Time.get_ticks_usec();var data:Dictionary
	if background:
		var copied:=Upload.snapshot(source,plain_roads)
		var snap:=Time.get_ticks_usec()
		var worker:=Thread.new();var ticket:=Retirement.watch(worker,self,[copied])
		check(worker.start(Upload.build.bind(copied,Vector3.ZERO))==OK,"existing leased worker starts private upload")
		while worker.is_alive():await process_frame
		data=worker.wait_to_finish()
		check(data.private_upload_info.thread!=OS.get_main_thread_id(),"actual texture/material/mesh submission runs off main")
		check(not data.mesh.has_meta("ground_cpu_cache"),"worker does not register scene-owned CPU cache")
		var finish:=Time.get_ticks_usec();Geometry.finish_upload(data)
		rows.append({"background":true,"snapshot_us":snap-began,"worker":data.private_upload_info,"finish_us":Time.get_ticks_usec()-finish,"wall_us":Time.get_ticks_usec()-began})
		Retirement.complete(ticket)
	else:
		var prepared:=Geometry.build(source,Vector3.ZERO,true)
		var upload_started:=Time.get_ticks_usec();data=Geometry.upload(prepared)
		rows.append({"background":false,"upload_us":Time.get_ticks_usec()-upload_started,"wall_us":Time.get_ticks_usec()-began})
	return data

func first_material_reference(source:Array)->WeakRef:
	# End the temporary nested Array/Dictionary expression before suspending
	# the cancellation coroutine; the test itself must not retain the input.
	return weakref(source[0].materials[0])

func retained(reference:WeakRef)->bool:
	return reference.get_ref()!=null

func start_gate(worker:Thread,gate:Gate,source:Array)->Error:
	return worker.start(Gate.work.bind(gate,source))

func missing_metadata_case(source:Array)->void:
	var member:Dictionary=source[0].duplicate();member.materials=[]
	for original:ShaderMaterial in source[0].materials:
		var material:ShaderMaterial=original.duplicate()
		material.remove_meta("terrain_height_image");material.remove_meta("ground_mask_image")
		member.materials.append(material)
	var result:=await execute([member],true)
	var heights:Texture2DArray=result.mesh.surface_get_material(0).get_shader_parameter("batch_heights")
	check(heights.get_layers()==1 and heights.get_layer_data(0).get_data()==Geometry.height_image(member.record).get_data(),"ordinary terrain without optional metadata uses the same worker height fallback")

func region_layers_case(source:Array)->void:
	var regions:Array=[]
	for i in source.size():
		var member:Dictionary=source[i].duplicate();member.record=member.record.duplicate()
		member.record.terrain_regions={};member.materials=[];member.keys=[]
		var mask:=Image.create(3,3,false,Image.FORMAT_RGBA8);mask.fill(Color(.15+.6*i,0,0,1))
		var material:ShaderMaterial=source[i].materials[0].duplicate()
		material.set_meta("ground_mask_image",mask)
		material.set_shader_parameter("ground_mask",ImageTexture.create_from_image(mask))
		material.set_shader_parameter("ground_enabled",true)
		material.set_shader_parameter("region_a_color",Color(.8,.15,.1,1))
		for slot in member.surfaces.size():member.materials.append(material);member.keys.append(Geometry.material_key(material))
		regions.append(member)
	check(regions[0].keys==regions[1].keys,"different per-source region masks belong to the same material batch")
	var oracle:=await execute(regions,false);var baseline:=await capture(oracle.mesh)
	var result:=await execute(regions,true)
	var masks:Texture2DArray=result.mesh.surface_get_material(0).get_shader_parameter("batch_ground_masks")
	var expected:Texture2DArray=oracle.mesh.surface_get_material(0).get_shader_parameter("batch_ground_masks")
	check(masks.get_layers()==2 and masks.get_layer_data(0).get_data()==expected.get_layer_data(0).get_data() and masks.get_layer_data(1).get_data()==expected.get_layer_data(1).get_data() and masks.get_layer_data(0).get_data()!=masks.get_layer_data(1).get_data(),"shared material preserves distinct region-mask layers exactly")
	var actual:=await capture(result.mesh)
	check(actual.get_data()==baseline.get_data(),"region-mask batching preserves the first submitted frame")
	visual.mesh=null

func dispatch_case(source:Array,runtime:bool,withdraw:bool)->void:
	var host:=Node3D.new();viewport.add_child(host)
	var batcher:=Ground.new();host.add_child(batcher);batcher.set_process(false)
	batcher.runtime_private_upload=runtime
	var nodes:Array=[]
	for member:Dictionary in source:
		var node:=MeshInstance3D.new();node.name=member.record.uuid
		node.mesh=Cpu.from_surfaces(member.surfaces,member.materials)
		node.set_meta("ground_batch_record",member.record);host.add_child(node);node.transform=member.transform
		nodes.append(node)
	batcher.request_sync(nodes)
	while not batcher._preparation.is_empty():batcher._prepare_step(0)
	check(batcher.groups.size()==1 and batcher.pending.size()==1,"real batch source collection creates one expected group")
	batcher._build_next(true)
	check(batcher._workers.size()==1 and batcher.private_upload_jobs==(1 if runtime else 0),"actual dispatch selects private upload only for eligible runtime sources")
	if withdraw:
		# The ordinary source lifetime signal invalidates its complete group
		# before the finished result is consumed, regardless of worker timing.
		nodes[0].free()
		check(batcher.groups.is_empty(),"source exit invalidates a pending upload immediately")
	while not batcher._workers.is_empty():
		if not batcher._workers[0].thread.is_alive():batcher._finish_worker(0)
		else:await process_frame
	if withdraw:
		check(batcher.rebuild_count==0 and batcher.get_child_count()==0,"late result cannot publish after its source generation is removed")
	else:
		check(batcher.rebuild_count==1 and batcher.groups.values()[0].data.mesh.has_meta("ground_cpu_cache"),"ordinary main commit installs one mesh and its CPU owner")
		check(batcher.private_upload_failures==0 and (batcher.private_upload_surfaces>0)==runtime,"real job counters account GPU preparation without a fallback")
		var group:Dictionary=batcher.groups.values()[0]
		var mesh:Mesh=group.data.mesh
		await Presented.drawn()
		check(group.visual.is_visible_in_tree() and mesh.get_surface_count()==1,"committed batch remains visible")
	batcher.clear();host.free()
	await process_frame

func cancel_case(source:Array,plain_roads:bool=false)->void:
	var copied:=Upload.snapshot(source,plain_roads);var reference:WeakRef=first_material_reference(copied)
	var gate:=Gate.new();var worker:=Thread.new();var ticket:=Retirement.watch(worker,self,[copied])
	var token:RefCounted=ticket.token
	check(start_gate(worker,gate,copied)==OK,"cancellation worker starts")
	copied=[]
	while not gate.is_ready():await process_frame
	var before:int=Engine.get_process_frames();Retirement.abandon(ticket)
	check(worker.is_alive() and token.is_cancelled(),"abandon does not join a live upload worker")
	await process_frame;await process_frame
	check(Engine.get_process_frames()>before and retained(reference) and retained(gate.mesh),"frames continue with the same input and output owners retained")
	gate.open()
	var deadline:=Time.get_ticks_msec()+5000
	while token.has_meta("admission_owner") and Time.get_ticks_msec()<deadline:await process_frame
	print("CANCEL_STATE ",JSON.stringify({"token_owner":token.has_meta("admission_owner"),"material_alive":retained(reference),"mesh_alive":retained(gate.mesh),"worker_alive":worker.is_alive(),"worker_started":worker.is_started()}))
	check(not token.has_meta("admission_owner") and not retained(reference) and not retained(gate.mesh),"abandoned result and material lease really release after join")

func road_case()->void:
	var source:=members()
	for member:Dictionary in source:
		# The upload contract consumes arrays, not a road authoring recipe. Keep
		# this compact synthetic geometry; the real 10-road probe covers records.
		member.record.erase("terrain_mesh");member.record.road_mesh={}
		var material:=StandardMaterial3D.new();material.albedo_color=Color(.7,.6,.4)
		material.albedo_texture=member.materials[0].get_shader_parameter("base_albedo")
		member.materials=[];member.keys=[]
		for slot in member.surfaces.size():member.materials.append(material);member.keys.append(Geometry.material_key(material))
	if not source[0].materials[0].has_method("get_shader_rid"):
		check(Upload.snapshot(source,true).is_empty(),"engine without preparation API retains old road upload")
		check(not "--require-native-road" in OS.get_cmdline_user_args(),"requested candidate engine API is available")
		return
	var copied:=Upload.snapshot(source,true);var original:StandardMaterial3D=source[0].materials[0]
	check(copied.size()==2 and copied[0].materials[0]!=original and copied[0].materials[0]==copied[1].materials[0],"road snapshot copies one material per batch key")
	check(copied[0].materials[0].albedo_texture==original.albedo_texture,"road snapshot shares the actual texture without upload or decode")
	original.roughness=.123
	check(copied[0].materials[0].roughness!=.123,"road private material is isolated from source parameter changes")
	original.roughness=1.
	var bad:Dictionary=source[0].duplicate();bad.record=bad.record.duplicate();bad.record.erase("road_mesh")
	check(Upload.snapshot([bad],true).is_empty(),"road candidate cannot admit unrelated Standard material batches")
	bad=source[0].duplicate();bad.materials=[original.duplicate()];bad.materials[0].next_pass=StandardMaterial3D.new()
	check(Upload.snapshot([bad],true).is_empty(),"road candidate rejects a shared next pass")
	var oracle:=await execute(source,false);var expected:=await capture(oracle.mesh)
	var uploaded:=await execute(source,true,true);var image:=await capture(uploaded.mesh)
	check(image.get_data()==expected.get_data(),"road private material first draw matches synchronous pixels")
	check(var_to_bytes(Cpu.capture(uploaded.mesh).surfaces)==var_to_bytes(Cpu.capture(oracle.mesh).surfaces),"road upload retains exact geometry and work")
	await cancel_case(source,true)
	Ground.private_road_upload_enabled=true
	await dispatch_case(source,true,false)
	await dispatch_case(source,true,true)
	await dispatch_case(source,false,false)
	Ground.private_road_upload_enabled=false

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/") or DisplayServer.get_name()=="headless":quit(2);return
	create_timer(120.).timeout.connect(func():quit(2))
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var logger:=Errors.new();OS.add_logger(logger)
	viewport=SubViewport.new();viewport.size=Vector2i(512,320);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.12,.14,.18);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.5;viewport.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,32,0);viewport.add_child(light)
	var camera:=Camera3D.new();camera.position=Vector3(4,14,20);viewport.add_child(camera);camera.look_at(Vector3(4,0,0));camera.current=true
	visual=MeshInstance3D.new();viewport.add_child(visual)
	var source:=members();var original:ShaderMaterial=source[0].materials[0]
	var copied:=Upload.snapshot(source)
	check(source[0].materials[0]!=source[1].materials[0] and source[0].keys==source[1].keys,"fixture has distinct live materials with the same already established batch keys")
	check(copied[0].materials[0]!=original and copied[0].materials[0]==copied[1].materials[0],"snapshot copies one equivalent batch material once, rather than once per source")
	check(copied[0].materials[0].get_shader_parameter("base_albedo")==original.get_shader_parameter("base_albedo"),"texture owner is shared without decode/upload/copy")
	original.set_shader_parameter("base_roughness",.123)
	check(copied[0].materials[0].get_shader_parameter("base_roughness")!=.123,"mutable source uniform does not alter private snapshot")
	original.set_shader_parameter("base_roughness",.92)
	var unsupported:Dictionary=source[0].duplicate();unsupported.materials=[StandardMaterial3D.new()]
	check(Upload.snapshot([unsupported]).is_empty(),"shared lazy StandardMaterial stays on the existing path")
	var chained:Dictionary=source[0].duplicate();chained.materials=[original.duplicate()]
	chained.materials[0].next_pass=StandardMaterial3D.new()
	check(Upload.snapshot([chained]).is_empty(),"shared next-pass material cannot bypass the private-worker ownership boundary")
	var oracle:Dictionary=await execute(source,false);var baseline:Image=await capture(oracle.mesh)
	check(baseline.get_data().size()>0 and baseline.get_pixel(256,180)!=baseline.get_pixel(0,0),"oracle contains actual terrain pixels")
	for i in 2:
		var result:Dictionary=await execute(source,true)
		var actual:Mesh=Cpu.capture(result.mesh);var expected:Mesh=Cpu.capture(oracle.mesh)
		check(var_to_bytes(actual.surfaces)==var_to_bytes(expected.surfaces) and var_to_bytes(actual.lods)==var_to_bytes(expected.lods) and actual.bounds==expected.bounds,"exact vertices, indices, LODs and bounds match synchronous upload")
		check(result.source_surfaces==oracle.source_surfaces and result.source_vertices==oracle.source_vertices and result.render_vertices==oracle.render_vertices,"no extra geometry work or reduced content")
		var material:ShaderMaterial=result.mesh.surface_get_material(0)
		check(material.get_shader_parameter("base_albedo")==original.get_shader_parameter("base_albedo") and material.get_shader_parameter("batch_enabled"),"final render material retains exact texture and layered batch settings")
		var height:Texture2DArray=material.get_shader_parameter("batch_heights")
		var expected_height:Texture2DArray=oracle.mesh.surface_get_material(0).get_shader_parameter("batch_heights")
		check(height.get_layers()==2 and height.get_layer_data(0).get_data()==expected_height.get_layer_data(0).get_data() and height.get_layer_data(1).get_data()==expected_height.get_layer_data(1).get_data() and height.get_layer_data(0).get_data()!=height.get_layer_data(1).get_data(),"distinct per-source height layers match the production upload")
		var image:Image=await capture(result.mesh)
		check(image.get_data()==baseline.get_data(),"first submitted frame is pixel-identical to synchronous material/mesh combination")
		visual.mesh=null;result={}
	check(not bool(original.get_shader_parameter("batch_enabled")),"worker never mutates the live source material")
	await cancel_case(source)
	await missing_metadata_case(source)
	await region_layers_case(source)
	Ground.private_layered_upload_enabled=true
	await dispatch_case(source,true,false)
	await dispatch_case(source,true,true)
	await dispatch_case(source,false,false)
	Ground.private_layered_upload_enabled=false
	await road_case()
	viewport.free();oracle={};copied=[];source=[];River.cache.clear()
	await process_frame
	OS.remove_logger(logger);check(logger.errors.is_empty(),"no engine or script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"timings":rows,"timing_contract":"Warm shared shaders, pixel readback excluded from upload intervals. Functional contract; not a cold-shader or full-map performance comparison."},"\t"))
	print("GROUND_PRIVATE_UPLOAD ",JSON.stringify({"checks":checks,"failures":failures,"timings":rows}))
	quit(0 if failures.is_empty() else 1)
