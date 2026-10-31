extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const House=preload("res://scripts/world3d/house_prefab.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Proxy=preload("res://scripts/world3d/distant_building_proxy.gd")
const Lod=preload("res://scripts/world3d/render_lod_preparation.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
# Each rerun keeps its own pixels and report; never overwrite the archived
# 2026-10-17 baseline when checking a later runtime-only change.
var OUT:String="D:/code/rmmo_runtime/review_artifacts/distant_proxy_regression_%d/"%int(Time.get_unix_time_from_system()*1000000.)
var checks:=0
var failures:=0
var scene:Node3D
var service:Node3D
var view:SubViewport
var camera:Camera3D
var evidence:Dictionary={"views":[]}
class Errors extends Logger:
	var errors:Array=[]
	func _log_error(_function:String,_file:String,_line:int,code:String,rationale:String,_notify:bool,_type:int,_traces:Array)->void:errors.append(code+" "+rationale)
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func settle_proxy(at:Vector3)->void:
	var deadline:=Time.get_ticks_msec()+20000;var quiet:=0
	while Time.get_ticks_msec()<deadline:
		service.tick(at);service._poll()
		quiet=quiet+1 if service._job.is_empty() else 0
		if quiet>=3 and not service._rows.is_empty():return
		await process_frame
func snapshot(label:String)->Dictionary:
	for i in 6:await process_frame
	await RenderingServer.frame_post_draw
	var path:=OUT+label+".png";view.get_texture().get_image().save_png(path)
	return {"label":label,"path":path,"camera":var_to_str(camera.transform),"fov":camera.fov,"visible_draws":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"visible_triangles":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"shadow_draws":view.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"sha256":FileAccess.get_sha256(path)}
func run()->void:
	create_timer(180).timeout.connect(func():quit(2));DirAccess.make_dir_recursive_absolute(OUT)
	var logger:=Errors.new();OS.add_logger(logger)
	var plan:=Blueprint.generate({"layout":"townhouse","floors":3,"style":"plaster","shutters":false,"dormers":2,"chimney":true})
	check(plan.ok,"generate representative three-storey house through the shared editor/MCP blueprint")
	var frozen:=House.bake(plan.records);check(frozen.ok,"bake actual floor roof door components without changing the master plan")
	var doc:=Doc.new();var registry:={"version":Blueprint.VERSION,"parameters":plan.parameters,"position":[0,0,0],"yaw":0.,"baked":true,"parts":{},"signatures":{}}
	for record:Dictionary in frozen.records:
		record.uuid="house_"+str(doc.records.size());record.building.id="review_house"
		registry.parts[record.building.part]=record.uuid;registry.signatures[record.building.part]="review"
		doc.records.append(record)
	doc.map_meta={"building_instances":{"review_house":registry}}
	var path:=preload("res://scripts/world3d/map_paths.gd").cache_directory("distant_review_%d"%Time.get_ticks_usec()).path_join("map.gltf")
	check(doc.save(path)==OK,"save real frozen native source with full ownership")
	var source_sha:=FileAccess.get_sha256(path);doc=Doc.open_file(path)
	check(doc!=null,"reopen actual native resources before visual and semantic checks")
	if doc==null:quit(1);return
	view=SubViewport.new();view.size=Vector2i(1280,960);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;view.msaa_3d=Viewport.MSAA_4X;root.add_child(view)
	var stage:=Node3D.new();view.add_child(stage)
	var environment:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.25,.3,.36);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.8,.86,1);env.ambient_light_energy=.5;env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;environment.environment=env;stage.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-35,0);light.shadow_enabled=true;light.directional_shadow_max_distance=1000;stage.add_child(light)
	var receiver:=MeshInstance3D.new();var plane_ground:=PlaneMesh.new();plane_ground.size=Vector2(40,40);receiver.mesh=plane_ground;receiver.position.y=-1.3
	var ground_material:=StandardMaterial3D.new();ground_material.albedo_color=Color(.26,.3,.2);receiver.material_override=ground_material;stage.add_child(receiver)
	camera=Camera3D.new();camera.far=2000;stage.add_child(camera);camera.current=true
	scene=doc.build();stage.add_child(scene);Stream.sync(scene,stage,Vector3.ZERO)
	var batcher:Node=scene.get_node("GroundRenderBatches");batcher.flush()
	service=Proxy.new();service.name="DistantBuildingProxy";scene.add_child(service);service.set_process(false)
	var diagnostics:Array=[]
	for node:Node3D in scene.get_meta("stream_meshes",{}).values():
		if not node is MeshInstance3D:continue
		diagnostics.append({"uuid":str(node.name),"cpu":node.mesh is Cpu,"fixture":node.get_meta("ground_batch_record",{}).has("fixture"),"eligible":Proxy._eligible(node),"vertices":preload("res://scripts/world3d/ground_batch_geometry.gd").vertex_count(node.mesh),"surfaces":node.mesh.get_surface_count(),"visible":node.visible})
	evidence.sources=diagnostics
	var original:=var_to_bytes(doc.records);var ids:Array=scene.get_meta("stream_by_id").keys();var bodies:Array=scene.get_meta("stream_bodies").keys()
	for setting:Array in [["near",Vector3(21,13,-27),50.],["middle",Vector3(130,65,-145),50.],["far",Vector3(180,90,-215),50.],["detail",Vector3(180,90,-215),8.]]:
		camera.position=setting[1];camera.look_at(Vector3(0,6,0));camera.fov=setting[2]
		Proxy.enabled=false;service.clear();var before:Dictionary=await snapshot(setting[0]+"_base")
		Proxy.enabled=true
		if setting[0] in ["far","detail"]:await settle_proxy(camera.position)
		else:service.tick(camera.position)
		var after:Dictionary=await snapshot(setting[0]+"_candidate")
		var levels:Array=[]
		for proxy:Dictionary in service._rows.values():levels.append(proxy.get("lod",{}))
		after.lod=levels
		print("PROXY_STATUS ",JSON.stringify(service.profile))
		evidence.views.append({"before":before,"after":after,"proxies":service.profile.active})
		check((service.profile.active>0) if setting[0] in ["far","detail"] else service.profile.active==0,"distance policy and same-camera rendered comparison "+setting[0])
		if setting[0]=="far":
			check(after.visible_draws<before.visible_draws,"actual far visible draw calls decrease")
			check(after.visible_triangles<before.visible_triangles,"actual far rendered triangles use index LODs")
			var submitted_match:=true
			for row:Dictionary in service._rows.values():
				var mesh:ArrayMesh=row.proxy.mesh
				var actual:Array=[]
				for slot:int in mesh.get_surface_count():
					var counts:Array=[]
					for indices:PackedInt32Array in Cpu.capture_lods(mesh,slot).values():counts.append(indices.size()/3)
					actual.append(counts)
				if actual!=row.get("lod",{}).get("triangles",[]):submitted_match=false
			check(submitted_match,"actual proxy GPU buffers contain the worker's final LOD tables")
		if setting[0]=="far":
			var key:String=service._rows.keys()[0];var active:Node3D=service._rows[key].proxy
			for i in 4:service.tick(camera.position);service._poll();await process_frame
			check(is_instance_valid(active) and service._rows.has(key) and service._rows[key].proxy==active,"repeated distance polling retains proxy without hide/rebuild oscillation")
	check(scene.get_meta("stream_by_id").keys()==ids and scene.get_meta("stream_bodies").keys()==bodies and var_to_bytes(doc.records)==original,"proxy leaves source UUIDs exact collision objects and author records unchanged")
	if not service._rows.is_empty():
		var key:String=service._rows.keys()[0];var row:Dictionary=service._rows[key];var member:Node3D=row.members[0].get_ref();member.hide()
		check(not service._rows.has(key),"floor visibility immediately withdraws affected proxy")
		member.show();await settle_proxy(camera.position)
		if not service._rows.is_empty():
			key=service._rows.keys()[0];var source:Node3D=service._rows[key].visuals[0].get_ref();source.position.x+=1;await process_frame
			check(not service._rows.has(key),"source pose invalidates proxy before the next distance poll")
	service.clear();service.tick(Vector3(0,0,300));service.clear()
	while not service._job.is_empty():service._poll();await process_frame
	check(service._rows.is_empty(),"cancelled worker cannot install stale proxy")
	await settle_proxy(Vector3(0,0,300));service.tick(Vector3.ZERO)
	check(service._rows.is_empty(),"near reentry restores original render layers")
	# Dense planar geometry isolates true index LOD generation from draw merging.
	var plane:=PlaneMesh.new();plane.subdivide_width=63;plane.subdivide_depth=63
	var arrays:Array=[plane.surface_get_arrays(0)];var bytes:=var_to_bytes(arrays);var worker:=Thread.new();worker.start(Lod.derive.bind(arrays))
	while worker.is_alive():await process_frame
	var derived:Dictionary=worker.wait_to_finish()
	check(not derived.is_empty() and not derived.lods[0].is_empty() and var_to_bytes(arrays)==bytes,"worker derives real index LODs with byte-exact base arrays")
	var cpu:=Cpu.new();cpu.surfaces=arrays;cpu.materials.append(StandardMaterial3D.new());cpu.bounds=plane.get_aabb();cpu.lods=derived.get("lods",[])
	var gpu:Mesh=cpu.restore();var gpu_surface:Dictionary=RenderingServer.mesh_get_surface(gpu.get_rid(),0)
	check(preload("res://tools/bridge_lod_assertions.gd").matches(gpu,cpu.lods),"actual GPU LOD indices and thresholds match worker output")
	check(cpu.collision_faces()==Cpu.capture(plane).collision_faces(),"index LODs leave exact collision triangle soup unchanged")
	var excluded:=MeshInstance3D.new();var cube:=BoxMesh.new();var transparent:=StandardMaterial3D.new();transparent.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;cube.material=transparent;excluded.mesh=cube
	check(not Proxy._eligible(excluded,{}),"transparent source stays independent")
	excluded.material_override=StandardMaterial3D.new();check(not Proxy._eligible(excluded,{}),"per-instance override stays independent")
	excluded.material_override=null;cube.material=ShaderMaterial.new();check(not Proxy._eligible(excluded,{}),"wind and arbitrary shader sources stay independent");excluded.free()
	check(FileAccess.get_sha256(path)==source_sha,"source native bytes and rollback master stay unchanged")
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors including notification-time invalidation")
	evidence.merge({"checks":checks,"failures":failures,"profile":service.profile.duplicate(),"source_path":path,"source_sha256":source_sha,"source_parts":plan.records.size(),"frozen_components":doc.records.size(),"lod":derived,"environment":{"resolution":[1280,960],"msaa":4,"light_degrees":[-45,-35,0],"ambient":.5,"exposure":1.}})
	# Scalar LOD counts only; never serialize thousands of index elements in reports.
	evidence.lod.erase("lods")
	FileAccess.open(OUT+"proxy_gpu.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"  "));view.free()
	print("DISTANT_PROXY_GPU checks=",checks," failures=",failures," report=",OUT+"proxy_gpu.json");quit(1 if failures else 0)
