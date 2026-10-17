extends SceneTree
## Isolated native save/reopen, actual renderer LODs and fixed-view quality A/B.
const Doc=preload("res://scripts/world3d/world_document.gd")
const T=preload("res://scripts/world3d/terrain_surface.gd")
const L=preload("res://scripts/world3d/terrain_render_lod.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Readback=preload("res://tools/bridge_lod_assertions.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/staged_far_20261017/"
var folder:String
var failures:=0
var evidence:Dictionary={"checks":[],"views":[],"measurements":[]}
var viewport:SubViewport
var camera:Camera3D
var map:Node3D
var batch:Node3D
class EntryHost extends Node3D:
	func _loading_stage(_stage:String)->void:pass
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_);evidence.checks.append({"ok":ok,"label":label_})
	if not ok:failures+=1
func material(name_:String,color:Color)->Dictionary:
	return {"name":name_,"color":[color.r,color.g,color.b,1.],"roughness":.85,"normal_strength":.45,"normal_path":folder.path_join("normal.png"),"tile_size":[2.,2.]}
func make_map()->String:
	var image:=Image.create(128,128,false,Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var n:=Vector3(.25*sin(x*.4),.25*cos(y*.4),1.).normalized();image.set_pixel(x,y,Color(n.x*.5+.5,n.y*.5+.5,n.z*.5+.5))
	image.save_png(folder.path_join("normal.png"))
	var doc:=Doc.new()
	for z in 2:
		for x in 2:
			var record:Dictionary=preload("res://tools/test_terrain_incremental.gd").fixture(64 if x==0 else 32)
			record.uuid="terrain_%d_%d"%[x,z];record.position=[x*64.+32.,0.,z*64.+32.]
			record.terrain_material=material("grass",Color(.28,.4,.17))
			record.terrain_depth_blend={"water_level":-.05,"shore_start":.02,"shore_end":.22,"rock_start":.08,"rock_end":.3,"bank_profile":"natural","steep_start":25.,"steep_end":65.,"transition_width":.8,"edge_noise":.15,"height_blend_strength":0.,"wet_darkening":.45,"wet_height":.15,"sand_material":material("sand",Color(.65,.54,.36)),"rock_material":material("rock",Color(.36,.38,.4)),"transition_material":material("soil",Color(.25,.17,.09))}
			var n:int=record.terrain_mesh.columns
			for row in n+1:
				for column in n+1:
					var wx:float=record.position[0]-64.+(float(column)/n-.5)*64.;var wz:float=record.position[2]-64.+(float(row)/n-.5)*64.
					record.terrain_mesh.heights[row*(n+1)+column]=.1*sin(wx*.08)+.08*cos(wz*.07)
			doc.records.append(record)
	var path:=folder.path_join("terrain.gltf");check(doc.save(path)==OK,"save real mixed-grid terrain with full riverbank PBR dependencies")
	var reopened=Doc.open_file(path)
	check(reopened!=null and reopened.records.size()==4,"native reopening restores all author identities")
	if reopened==null:return ""
	map=reopened.build();viewport.add_child(map)
	var nodes:Array=[];var before:Array=[]
	for node:MeshInstance3D in map.get_children():
		nodes.append(node);before.append(var_to_bytes(Cpu.capture(node.mesh).surfaces))
		var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();shape.shape=node.mesh.create_trimesh_shape();body.add_child(shape);map.add_child(body);body.transform=node.transform
	batch=Batch.new();map.add_child(batch);batch.set_process(false);batch.sync(nodes);batch.flush()
	var preserved:=true
	for i in nodes.size():preserved=preserved and before[i]==var_to_bytes(Cpu.capture(nodes[i].mesh).surfaces)
	check(preserved,"derived batch never changes source positions normals UVs indices or exact collision faces")
	var levels:=0;var bytes:=0;var base_indices:=0
	for group:Dictionary in batch.groups.values():
		var mesh:Mesh=group.visual.mesh;var cpu:Mesh=Cpu.capture(mesh)
		check(Readback.matches(mesh,cpu.lods),"actual renderer thresholds/index buffers match worker-owned LOD data")
		for slot in cpu.surfaces.size():
			base_indices+=cpu.surfaces[slot][Mesh.ARRAY_INDEX].size()
			for indices:PackedInt32Array in cpu.lods[slot].values():levels+=1;bytes+=indices.size()*4
	check(levels>0,"native terrain enters real render-only LOD batches")
	evidence.geometry={"levels":levels,"extra_index_bytes":bytes,"base_indices":base_indices,"author_sha256":FileAccess.get_sha256(path),"native_bytes":FileAccess.get_file_as_bytes(path).size(),"normal_sha256":FileAccess.get_sha256(folder.path_join("normal.png")),"normal_source_bytes":FileAccess.get_file_as_bytes(folder.path_join("normal.png")).size(),"normal_decoded_bytes":128*128*3,"normal_gpu_rgba8_mip_budget_bytes":int(128*128*4*4./3.)}
	return path
func policy(enabled:bool)->void:
	L.enabled=enabled;L.update(map,camera.global_position)
	for node:Node in map.get_children():
		if not node is MeshInstance3D:continue
		for slot in node.mesh.get_surface_count():
			var mat:Material=node.get_active_material(slot)
			if mat is ShaderMaterial:mat.set_shader_parameter("far_detail_enabled",enabled)
	for group:Dictionary in batch.groups.values():
		var mesh:Mesh=group.visual.mesh
		for slot in mesh.get_surface_count():
			var mat:Material=mesh.surface_get_material(slot)
			if mat is ShaderMaterial:mat.set_shader_parameter("far_detail_enabled",enabled)
func capture(label_:String)->Dictionary:
	for i in 8:await process_frame
	await RenderingServer.frame_post_draw
	var image:Image=viewport.get_texture().get_image();image.save_png(folder.path_join(label_+".png"))
	return {"label":label_,"image":image,"primitives":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
func sample(label_:String)->void:
	for i in 12:await process_frame
	var times:Array=[]
	for i in 40:
		await process_frame
		times.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
	evidence.measurements.append({"label":label_,"gpu_ms":times})
func image_delta(a:Image,b:Image)->Dictionary:
	var left:=a.get_data();var right:=b.get_data();var total:=0;var maximum:=0
	if left==right:return {"mean":0.,"max":0.}
	for i in left.size():
		var difference:=absi(left[i]-right[i]);total+=difference;maximum=maxi(maximum,difference)
	return {"mean":float(total)/maxi(1,left.size())/255.,"max":float(maximum)/255.}
func holes_case(path:String)->void:
	var source=Doc.open_file(path);var record:Dictionary=source.records[0].duplicate(true)
	record.uuid="hole_steep_bank";record.position=[0.,0.,0.];record.terrain_mesh.columns=32;record.terrain_mesh.rows=32;record.terrain_mesh.heights.resize(33*33);record.terrain_mesh.holes.resize(32*32);record.terrain_mesh.holes.fill(false)
	for z in 33:
		for x in 33:record.terrain_mesh.heights[z*33+x]=clampf((absf(x-16.)-3.)*4.,0.,9.)
	for z in [15,16]:record.terrain_mesh.holes[z*32+15]=true
	var doc:=Doc.new();doc.records=[record];var hole_path:=folder.path_join("hole_bank.gltf")
	check(doc.save(hole_path)==OK,"save actual steep bank and two-cell hole fixture")
	map.free();doc=Doc.open_file(hole_path);map=doc.build();viewport.add_child(map)
	var visual:MeshInstance3D=map.get_child(0);var bytes:=var_to_bytes(Cpu.capture(visual.mesh).surfaces)
	var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();shape.shape=visual.mesh.create_trimesh_shape();body.add_child(shape);map.add_child(body)
	batch=Batch.new();map.add_child(batch);batch.set_process(false);batch.sync([visual]);batch.flush()
	check(batch.groups.is_empty(),"topology with real holes retains exact full render/collision fallback")
	for v:Dictionary in [{"name":"hole_bank_near","eye":Vector3(-10,10,12),"fov":70.},{"name":"hole_bank_far","eye":Vector3(0,90,300),"fov":20.}]:
		camera.position=v.eye;camera.fov=v.fov;camera.look_at(Vector3.ZERO)
		policy(false);var a:Dictionary=await capture(v.name+"_baseline");policy(true);var b:Dictionary=await capture(v.name+"_candidate")
		evidence.views.append({"name":v.name,"baseline_primitives":a.primitives,"candidate_primitives":b.primitives,"image_delta":image_delta(a.image,b.image)})
		check(a.primitives==b.primitives and var_to_bytes(Cpu.capture(visual.mesh).surfaces)==bytes,"steep cut edges and hole boundaries remain exact: "+v.name)
	await physics_frame;await process_frame
	var hit:=viewport.find_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-1,10,.5),Vector3(-1,-6,.5)))
	check(hit.is_empty(),"actual physical ray still passes through the authored hole")
	evidence.hole_map={"path":hole_path,"sha256":FileAccess.get_sha256(hole_path)}
func audit_cutout()->void:
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"cutout_http.json"));var path:String=report.asset.import.asset_path
	var compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
	var manifest_path:String=compiled.index_path(path)
	check(FileAccess.file_exists(manifest_path),"actual native manifest exists; no source-only import is mistaken for native acceptance")
	if not FileAccess.file_exists(manifest_path):return
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var product:String=compiled.directory().path_join(manifest.payload_sha+".scn")
	var loaded:Dictionary=compiled.read(path)
	check(loaded.get("hit",false) and loaded.get("packed")!=null,"cutout actual immutable native product reopens through production validation")
	var stats:Dictionary=preload("res://scripts/world3d/compiled_asset_footprint.gd").measure(loaded.packed)
	check(not stats.is_empty() and stats.textures==1,"cutout unique texture/native costs measured from actual reopened product")
	evidence.cutout_audit={"source":path,"source_sha256":FileAccess.get_sha256(path),"source_bytes":FileAccess.get_file_as_bytes(path).size(),"native":product,"native_sha256":FileAccess.get_sha256(product),"native_bytes":FileAccess.get_file_as_bytes(product).size(),"generator":manifest.generator,"stats":stats,"note":"texture/mesh storage accounting is not measured process RSS/VRAM"}
	loaded.clear()
func prepare_cancelled(attempt:RefCounted,host:Node3D,state:Dictionary)->void:
	state.error=await attempt.prepare(host,host,Vector3(0,.9,0));state.done=true
func initial_cancellation_case()->void:
	var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.1,0),Vector3(8,.2,8))
	var host:=EntryHost.new();viewport.add_child(host);var content:Node3D=doc.build();host.add_child(content)
	var attempt:=preload("res://scripts/world3d/building_entry_transaction.gd").new();var adapter:=preload("res://scripts/world3d/local_entry_authority.gd").new()
	check(attempt.begin(adapter,content,"cancel_session","cancel_world","cancel_map","revision",Vector3.ZERO,"entry").ok,"isolated initial preparation owns a real authority ticket")
	var state:Dictionary={"done":false,"error":""};prepare_cancelled(attempt,host,state)
	var publication_deadline:=Time.get_ticks_msec()+5000
	while attempt.state_applied_frame<0 and not state.done and Time.get_ticks_msec()<publication_deadline:await process_frame
	check(attempt.state_applied_frame>=0 and not state.done,"initial preparation really waits for the next physics publication")
	host.free();var deadline:=Time.get_ticks_msec()+5000
	while not state.done and Time.get_ticks_msec()<deadline:await process_frame
	check(state.done and state.error=="entry_cancelled" and not attempt.gate.can_play(),"destroyed initial world resumes safely without dereferencing it or activating entry")
	attempt.cancel("test_complete")
func run()->void:
	create_timer(180).timeout.connect(func():print("STAGED_FAR_GPU_TIMEOUT");quit(2))
	folder=OUT.path_join("terrain_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	viewport=SubViewport.new();viewport.size=Vector2i(1280,800);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.use_taa=false;root.add_child(viewport)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.1,.13,.18);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.45;viewport.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-52,-35,0);sun.shadow_enabled=true;sun.directional_shadow_max_distance=1200.;viewport.add_child(sun)
	camera=Camera3D.new();camera.current=true;camera.far=1800.;viewport.add_child(camera)
	var path:=make_map()
	if path.is_empty():quit(1);return
	for view:Dictionary in [{"name":"near","position":Vector3(0,55,90),"fov":70.},{"name":"detail","position":Vector3(-28,6,12),"fov":58.},{"name":"mid","position":Vector3(0,100,230),"fov":38.},{"name":"far","position":Vector3(0,240,650),"fov":16.}]:
		camera.position=view.position+Vector3(64,0,64);camera.fov=view.fov;camera.look_at((Vector3(-20,0,0) if view.name=="detail" else Vector3.ZERO)+Vector3(64,0,64))
		policy(false);var a:Dictionary=await capture(view.name+"_baseline")
		var aa:Dictionary=await capture(view.name+"_repeat")
		policy(true);var b:Dictionary=await capture(view.name+"_candidate")
		var delta:Dictionary=image_delta(a.image,b.image)
		evidence.views.append({"name":view.name,"baseline_primitives":a.primitives,"repeat_primitives":aa.primitives,"candidate_primitives":b.primitives,"baseline_draw_calls":a.draw_calls,"candidate_draw_calls":b.draw_calls,"image_delta":delta})
		check(a.primitives==aa.primitives,"A/A submitted primitive count is stable: "+view.name)
		if view.name in ["near","detail"]:check(a.primitives==b.primitives and delta.max<=1./255. and delta.mean<.000001,"near base geometry stays exact and image stays within one output LSB: "+view.name)
		if view.name=="far":check(b.primitives<a.primitives*.65,"far policy reduces actual submitted primitives beyond A/A noise")
	policy(false);await sample("baseline_a");await sample("baseline_a_repeat")
	policy(true);await sample("candidate_b");policy(false);await sample("baseline_a_return");policy(true);await sample("candidate_b_repeat")
	await physics_frame;await process_frame
	var hit:=viewport.find_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(44,10,44),Vector3(44,-5,44)))
	check(not hit.is_empty() and absf(hit.position.y-(.1*sin(-20*.08)+.08*cos(-20*.07)))<.002,"far render LOD preserves original physical terrain height")
	check(FileAccess.get_sha256(path)==evidence.geometry.author_sha256,"all distance changes leave saved author data unchanged")
	await holes_case(path);audit_cutout();await initial_cancellation_case()
	evidence.failures=failures;evidence.media=folder
	FileAccess.open(OUT+"terrain_gpu.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"  "))
	viewport.free();print("STAGED_FAR_GPU failures=",failures," media=",folder);quit(1 if failures else 0)
