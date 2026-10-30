extends "res://tools/test_cpu_river_materials_gpu.gd"
## Actual document/index/spawn, original collision, and first rendered pixels.
const Upload=preload("res://scripts/world3d/prepared_cpu_upload.gd")
var camera:Camera3D
var timings:Array=[]

func water_record(sloped:bool=false)->Dictionary:
	var value:={"uuid":"visible_water","kind":"box","surface_id":"water","collision":"walk","position":[0,0,0],"rotation":[0,17,0],"size":[8,.2,8],"color":[.2,.4,.3],"channel_mesh":{"uv_origin":[0,0,0],"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]]},"water_depth_effect":{"absorption":.45,"shallow_color":[.24,.42,.34],"deep_color":[.055,.16,.14]}}
	if sloped:value.channel_mesh.elevations=[[0.,0.,1.5,1.5]]
	return value

func draw_spec(spec:Dictionary)->Image:
	var started:=Time.get_ticks_usec()
	var node:=Stream._spawn(viewport,spec);viewport.add_child(node)
	var install_us:=Time.get_ticks_usec()-started
	await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image()
	timings.append({"install_us":install_us,"through_draw_us":Time.get_ticks_usec()-started,"surfaces":node.mesh.get_surface_count()})
	node.free()
	await process_frame
	return image

func prepare_channel(record_:Dictionary)->Dictionary:
	var arrays:Array=preload("res://scripts/world3d/channel_surface.gd").arrays(record_)
	return {"arrays":arrays,"bounds":preload("res://scripts/world3d/procedural_surface_bounds.gd").bounds(arrays),"upload":Upload.prepare(arrays,Upload.MAX_BYTES)}

func case_test(sloped:bool,worker_prepared:bool=false)->void:
	var authored:=water_record(sloped);var original:=var_to_bytes(authored)
	var doc:=Doc.new();doc.load_box_meshes={}
	River.water_visible_surfaces_enabled=false
	if worker_prepared:
		var worker:=Thread.new();check(worker.start(prepare_channel.bind(authored))==OK,"uncached channel worker starts")
		while worker.is_alive():await process_frame
		var prepared_channel:Dictionary=worker.wait_to_finish()
		doc.load_surface_arrays[authored.uuid]=prepared_channel.arrays
		doc.load_surface_bounds[authored.uuid]=prepared_channel.bounds
		doc.load_surface_uploads[authored.uuid]=prepared_channel.upload
	else:
		var seed:MeshInstance3D=doc._mesh(authored);seed.free()
		var cooked:=Cook.pack(doc.load_box_meshes,"test_source","test_generator")
		doc.load_box_meshes=Cook.restore(cooked)
	doc.load_immutable_records=true
	var old_node:MeshInstance3D=doc._mesh(authored)
	check(not old_node.has_meta("paint_error"),"real channel fixture accepted")
	var source:Mesh=old_node.mesh;var original_arrays:=var_to_bytes(source.surfaces)
	var old:=Stream._spec(old_node);old_node.free()
	var old_faces:PackedVector3Array=old.collision_mesh.collision_faces()
	var visible:Array[int]=[]
	for slot:int in old.surface_overrides.size():
		if old.surface_overrides[slot]!=River.hidden_slab:visible.append(slot)
	check(visible.size()>0 and visible.size()<source.get_surface_count(),"fixture includes actual water and hidden slab faces")
	# Exercise existing packed buffers too: projection must borrow selected rows,
	# not call mesh_prepare_surface_from_arrays again or keep removed rows.
	var packet:Upload.Payload=source.get_meta(Upload.META) if source.has_meta(Upload.META) else Upload.prepare(source.surfaces,Upload.MAX_BYTES,source.lods)
	check(packet!=null,"actual native surface payload prepared once")
	if packet!=null:Upload.attach(source,packet)
	River.hidden_slab=null;River.water_visible_surfaces_enabled=true
	var node:MeshInstance3D=doc._mesh(authored)
	var actual:=Stream._spec(node);node.free()
	check(River.hidden_slab==null,"runtime indexing never constructs a discard shader")
	check(actual.mesh is Cpu and actual.mesh.get_surface_count()==visible.size(),"runtime render mesh contains only visible surfaces")
	check(actual.mesh!=source and source.source_reference==null and actual.mesh.source_reference==null,"projection and original remain GPU-free before spawn")
	check(var_to_bytes(source.surfaces)==original_arrays,"original CPU source and all authored slab faces stay intact")
	check(actual.collision_mesh==old.collision_mesh and actual.collision_mesh.collision_faces()==old_faces,"collision retains exactly the original solid and triangles")
	check(actual.transform==old.transform and actual.chunk_min==old.chunk_min and actual.chunk_max==old.chunk_max,"world pose and streaming demand coverage unchanged")
	var second_node:MeshInstance3D=doc._mesh(authored)
	check(second_node.mesh==actual.mesh,"repeated placements share one projected CPU/GPU generation")
	second_node.free()
	var prepared:Variant=actual.mesh.get_meta(Upload.META) if actual.mesh.has_meta(Upload.META) else null
	check(prepared!=null and prepared.surfaces.size()==visible.size(),"projected upload payload has only selected original slots")
	if actual.mesh.get_surface_count()==visible.size():
		for slot:int in visible.size():
			check(var_to_bytes(actual.mesh.surfaces[slot])==var_to_bytes(source.surfaces[visible[slot]]),"visible vertex/index/UV/normal buffers unchanged")
			check(actual.mesh.materials[slot]==actual.surface_overrides[slot] and actual.surface_overrides[slot]==old.surface_overrides[visible[slot]],"GPU mesh starts with final water material, not an unused original")
	var installed_before:int=Upload.installed_surfaces
	var first_render:=Stream._spawn(viewport,actual);viewport.add_child(first_render)
	var second_render:=Stream._spawn(viewport,actual);viewport.add_child(second_render)
	var gpu_owner:WeakRef=weakref(first_render.mesh)
	check(first_render.mesh==second_render.mesh and Upload.installed_surfaces-installed_before==visible.size(),"simultaneous placements upload each selected surface only once")
	first_render.free()
	check(gpu_owner.get_ref()==second_render.mesh,"releasing one placement preserves the other's GPU owner")
	second_render.free();RenderingServer.force_sync()
	check(gpu_owner.get_ref()==null,"last placement releases GPU mesh while CPU directory stays alive")
	# A material variant must not reuse another placement's material or remain
	# pinned by the source cache after its final owner leaves.
	var variant_record:Dictionary=authored.duplicate(true);variant_record.water_depth_effect.absorption=.73
	var variant_node:=MeshInstance3D.new();variant_node.mesh=source
	River.apply(variant_node,variant_record,{},null,true,true)
	var variant_owner:WeakRef=weakref(variant_node.mesh)
	check(variant_node.mesh!=actual.mesh and variant_node.mesh.materials[0]!=actual.mesh.materials[0],"different water material gets an independent projection")
	variant_node.free()
	check(variant_owner.get_ref()==null,"source cache cannot pin a departed projection")
	variant_node=MeshInstance3D.new();variant_node.mesh=source
	River.apply(variant_node,variant_record,{},null,true,true)
	check(source.get_meta(River.WATER_PROJECTIONS_META).size()==2,"expired projections are removed before rebuilding")
	variant_node.free()
	for position_:Vector3 in [Vector3(9,7,12),Vector3(9,.2,12),Vector3(9,-5,12)]:
		camera.position=position_;camera.look_at(Vector3.ZERO)
		var before:=await draw_spec(old);var after:=await draw_spec(actual);var again:=await draw_spec(old)
		var difference:=image_delta(before,after);var control:=image_delta(before,again)
		check(control.max==0. and difference.max<=2./255. and difference.mean<=1./255.,"above/edge/below A/B/A pixels preserve hidden faces: "+str(difference))
	check(var_to_bytes(authored)==original,"authored channel is unchanged")
	# Editor remains a full editable solid with its existing slot layout.
	doc.load_immutable_records=false
	var editable:MeshInstance3D=doc._mesh(authored)
	check(not editable.mesh is Cpu and editable.mesh.get_surface_count()==source.get_surface_count(),"editor retains original editable surfaces")
	editable.free()
	old.clear();actual.clear();doc=null;source=null;packet=null;prepared=null;River.cache.clear()
	RenderingServer.force_sync()

func excluded_projection_cases()->void:
	var authored:=water_record();var doc:=Doc.new();doc.load_box_meshes={}
	var seed:MeshInstance3D=doc._mesh(authored);seed.free()
	var data:=Cook.restore(Cook.pack(doc.load_box_meshes,"test_source","test_generator"))
	var source:Mesh=data.values()[0].mesh
	for property:String in ["material_override","material_overlay"]:
		var node:=MeshInstance3D.new();node.mesh=source
		var material:=StandardMaterial3D.new();node.set(property,material)
		River.apply(node,authored,{},null,true,true)
		check(node.mesh==source and node.get(property)==material,"global "+property+" retains every original surface")
		node.free()
	# Exercise a selected slot's actual native LOD buffer through GPU restore,
	# not only equality of the script-side source arrays.
	# Channels normally use unindexed triangle soup; native LODs require an
	# indexed base surface. Build an equivalent indexed fixture first.
	var top:Array=source.surfaces[0].duplicate()
	var indices:=PackedInt32Array();indices.resize(top[Mesh.ARRAY_VERTEX].size())
	for index:int in indices.size():indices[index]=index
	top[Mesh.ARRAY_INDEX]=indices;source.surfaces[0]=top
	source.lods.resize(source.get_surface_count());source.lods.fill({})
	source.lods[0]={2.5:PackedInt32Array([0,1,2])}
	var packet:=Upload.prepare(source.surfaces,Upload.MAX_BYTES,source.lods)
	check(packet!=null,"LOD fixture has a prepared native upload")
	check(packet!=null and not packet.surfaces[0].get("lods",[]).is_empty(),"indexed fixture contains actual native LOD bytes")
	Upload.attach(source,packet)
	var lod_node:=MeshInstance3D.new();lod_node.name="lod_water";lod_node.mesh=source
	River.apply(lod_node,authored,{},null,true,true)
	var lod_spec:=Stream._spec(lod_node);lod_node.free()
	var lod_render:=Stream._spawn(viewport,lod_spec)
	check(Cpu.capture_lods(lod_render.mesh,0)==source.lods[0],"selected LOD indices survive packed GPU upload and readback")
	lod_render.free();lod_spec.clear();packet=null
	var hidden:=Cpu.new();hidden.bounds=source.bounds
	hidden.surfaces=[source.surfaces[1]];hidden.materials.append(source.materials[1])
	var node:=MeshInstance3D.new();node.name="all_hidden";node.mesh=hidden
	River.apply(node,authored,{},null,true,true)
	check(node.mesh.get_surface_count()==0 and node.get_meta("collision_solid")==hidden,"all-hidden geometry retains collision without a rendered surface")
	var spec:=Stream._spec(node);node.free()
	var rendered:=Stream._spawn(viewport,spec);viewport.add_child(rendered)
	await RenderingServer.frame_post_draw
	check(rendered.mesh.get_surface_count()==0,"empty projection spawns without uploading hidden geometry")
	rendered.free();spec.clear();doc=null;data.clear();source=null;hidden=null

func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	create_timer(120).timeout.connect(func():quit(2))
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	viewport=SubViewport.new();viewport.size=Vector2i(256,192);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.use_taa=false;root.add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.12,.14,.18);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.6;viewport.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,32,0);viewport.add_child(light)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=12;camera.current=true;viewport.add_child(camera)
	var floor:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(30,.5,30);floor.mesh=box;floor.position.y=-2;viewport.add_child(floor)
	await case_test(false);await case_test(true);await case_test(true,true);await excluded_projection_cases()
	viewport.free();River.cache.clear();RenderingServer.force_sync()
	print("WATER_VISIBLE_SURFACES ",JSON.stringify({"passed":passed,"failures":failures,"timings":timings}))
	quit(1 if failures else 0)
