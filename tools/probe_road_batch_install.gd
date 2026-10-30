extends SceneTree
## Reproduce a recorded slow batch from immutable map records, without loading
## the rest of the town. Installation and its first real draw are both measured.
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Document=preload("res://scripts/world3d/world_document.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
const Bounds=preload("res://scripts/world3d/procedural_surface_bounds.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Geometry=preload("res://scripts/world3d/ground_batch_geometry.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const Presented=preload("res://scripts/util/frame_presentation.gd")
const IDS=["21ca0dba906e502e8361","29a1d7068f1d7535a184","4aa4cbdbd03dfe0005db","51f4a22c2b64c3a5a58d","583a6f2263547c021536","5c22d0c2a4fd43f5d7eb","6935bda740b22900feee","7ca7e64de3f502bb4ec7","b5c0c110df433a58b602","efa5337e41cec39783c3"]
var output:=""
var map_path:=""
var failures:Array=[]
var frames:Array=[]
var phase:="setup"
var last:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func observe()->void:
	var now:=Time.get_ticks_usec()
	if last>0:frames.append({"phase":phase,"at_us":now,"us":now-last})
	last=now
static func private_upload(data:Dictionary)->Dictionary:
	var began:=Time.get_ticks_usec()
	# This flag suppresses another material clone inside the established private
	# uploader. This probe has three plain, exclusively owned Standard materials.
	data.private_layered_materials=true
	var result:=Geometry.upload_private(data)
	result.worker_upload_us=Time.get_ticks_usec()-began
	return result
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
		if arg.begins_with("--map="):map_path=arg.trim_prefix("--map=").replace("\\","/")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/") or not map_path.begins_with("D:/code/rmmo_runtime/review_artifacts/"):quit(2);return
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size=Vector2i(512,512)
	root.use_taa=false;root.scaling_3d_mode=Viewport.SCALING_3D_MODE_BILINEAR;root.scaling_3d_scale=1.
	var map_sha:=FileAccess.get_sha256(map_path)
	var json:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(map_path))
	var compact:Array=[]
	for id:String in IDS:
		for record:Dictionary in json.nodes[0].extras.rmmo_records:
			if record.uuid=="pavement_"+id:compact.append(record);break
	check(compact.size()==10,"exact ten recorded pavement identities")
	var began:=Time.get_ticks_usec()
	var decoded:=Store.read_records(compact,map_path,"D:/code/rmmo_runtime",null,1,true)
	check(decoded.get("ok",false),"immutable record references resolve")
	if not decoded.get("ok",false):quit(1);return
	var doc:=Document.new();doc.load_immutable_records=true
	doc.load_paint_validation={};doc.load_texture_checks={};doc.load_material_pool={}
	var members:Array=[];var nodes:Array=[];var origin:=Vector3.ZERO
	for record:Dictionary in decoded.records:
		var arrays:=Road.arrays(record)
		doc.load_surface_arrays[record.uuid]=arrays;doc.load_surface_bounds[record.uuid]=Bounds.bounds(arrays)
		var node:MeshInstance3D=doc._mesh(record)
		nodes.append(node)
		check(node.mesh is Cpu and not node.has_meta("paint_error"),"CPU-only painted source "+str(record.uuid))
		if not node.mesh is Cpu:quit(1);return
		var materials:Array=[];var keys:Array=[]
		for slot:int in node.mesh.get_surface_count():
			var material:Material=node.get_surface_override_material(slot)
			if material==null:material=node.mesh.surface_get_material(slot)
			if node.material_override!=null:material=node.material_override
			materials.append(material);keys.append(Geometry.material_key(material))
		members.append({"record":record,"transform":node.transform,"surfaces":node.mesh.surfaces,"materials":materials,"keys":keys})
		origin+=node.position
	origin/=members.size()
	var source_us:=Time.get_ticks_usec()-began
	var worker:=Thread.new();began=Time.get_ticks_usec()
	check(worker.start(Geometry.build.bind(members,origin,true))==OK,"normal CPU batch build starts")
	while worker.is_alive():await process_frame
	var data:Dictionary=worker.wait_to_finish();var build_us:=Time.get_ticks_usec()-began
	check(data.slots.size()==3 and data.render_vertices==45264,"recorded batch matches: three surfaces and 45264 vertices")
	var descriptions:Array=[]
	var reference_slots:Array=[]
	for row:Dictionary in data.slots:
		descriptions.append({"class":row.material.get_class(),"name":row.material.resource_name,"vertices":row.arrays[Mesh.ARRAY_VERTEX].size(),"key":Geometry.material_key(row.material)})
		reference_slots.append(row.duplicate())
	var stage:=Node3D.new();root.add_child(stage)
	var camera:=Camera3D.new();camera.position=Vector3(0,30,30);stage.add_child(camera);camera.look_at(Vector3.ZERO);camera.current=true
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-20,0);stage.add_child(light)
	for i in 60:await process_frame
	var diagnostic:bool="--gdb-wait" in OS.get_cmdline_user_args()
	if diagnostic:
		FileAccess.open(output.get_base_dir().path_join("phase.log"),FileAccess.WRITE).store_line("ROAD_BATCH_READY")
		# A scene timer advances by simulation delta, which all-stop debugging
		# distorts. Explicit observer handshake gates the exact measured call.
		var deadline:=Time.get_ticks_msec()+90000
		while not FileAccess.file_exists(output.get_base_dir().path_join("gdb_ready")) and Time.get_ticks_msec()<deadline:await process_frame
		if not FileAccess.file_exists(output.get_base_dir().path_join("gdb_ready")):quit(2);return
	Trace.minimum_event_us=0;Trace.start();process_frame.connect(observe)
	phase="install";var install_started:=Time.get_ticks_usec();last=install_started
	var background:bool="--background-real-batch" in OS.get_cmdline_user_args()
	var preparation_us:=0;var finish_us:=0;var uploaded:Dictionary
	if background:
		for row:Dictionary in data.slots:
			check(row.material.has_method("get_shader_rid"),"isolated engine exposes shader preparation without material RID")
			if not row.material.has_method("get_shader_rid"):quit(2);return
			var original:Material=row.material
			row.material=original.duplicate()
			check(row.material!=original and Geometry.material_key(row.material)==Geometry.material_key(original),"private material keeps the exact grouping value")
			# Initialize the private StandardMaterial key on main. Its queued
			# flush and worker get_rid now take the unchanged-key read-only branch.
			row.material.call("get_shader_rid")
		preparation_us=Time.get_ticks_usec()-install_started
		var uploader:=Thread.new();check(uploader.start(private_upload.bind(data))==OK,"private real batch uploader starts")
		phase="worker_upload"
		while uploader.is_alive():await process_frame
		uploaded=uploader.wait_to_finish();var finish_started:=Time.get_ticks_usec()
		Geometry.finish_upload(uploaded);finish_us=Time.get_ticks_usec()-finish_started
	else:uploaded=Geometry.upload(data)
	var install_finished:=Time.get_ticks_usec()
	var visual:=MeshInstance3D.new();visual.mesh=uploaded.mesh;stage.add_child(visual)
	var attach_finished:=Time.get_ticks_usec();phase="first_draw"
	await Presented.drawn()
	var draw_finished:=Time.get_ticks_usec();phase="steady"
	for i in 30:await process_frame
	process_frame.disconnect(observe)
	var trace:=Trace.stop()
	check(uploaded.mesh.get_surface_count()==3,"installed surface count")
	var stored:Array=uploaded.mesh.get("_surfaces")
	for i:int in data.slots.size():
		check(uploaded.mesh.surface_get_material(i)==data.slots[i].material,"same material owner "+str(i))
		# Engine packing quantizes normals/UVs; decoded floats are not a byte
		# identity contract. Compare GPU buffers and retained source independently.
		for channel:String in ["vertex_data","attribute_data","skin_data","index_data"]:
			check(stored[i].get(channel,PackedByteArray())==data.slots[i].prepared_surface.get(channel,PackedByteArray()),"exact packed "+channel+" "+str(i))
		check(var_to_bytes(Cpu.capture(uploaded.mesh).surfaces[i])==var_to_bytes(data.slots[i].arrays),"exact retained CPU geometry "+str(i))
	check(FileAccess.get_sha256(map_path)==map_sha,"snapshot content unchanged")
	if background:
		# Validation is outside measured upload/draw. The second candidate draw
		# catches texture-streaming changes between sequential images as well.
		var first_image:=root.get_texture().get_image()
		var sampled_colors:Dictionary={}
		for y in range(0,first_image.get_height(),8):
			for x in range(0,first_image.get_width(),8):sampled_colors[first_image.get_pixel(x,y).to_rgba32()]=true
		check(sampled_colors.size()>8,"real pavement view contains varied rendered pixels")
		var reference_data:=data.duplicate();reference_data.slots=reference_slots
		reference_data.erase("private_layered_materials")
		var reference:=Geometry.upload(reference_data)
		visual.mesh=reference.mesh;await Presented.drawn()
		var reference_image:=root.get_texture().get_image()
		visual.mesh=uploaded.mesh;await Presented.drawn()
		var final_image:=root.get_texture().get_image()
		check(first_image.get_data()==reference_image.get_data() and final_image.get_data()==reference_image.get_data(),"actual source and private materials render identical pixels across A/B/A")
	var report:={"diagnostic":diagnostic,"background":background,"preparation_us":preparation_us,"finish_us":finish_us,"worker_upload_us":uploaded.get("worker_upload_us",0),"map_sha256":map_sha,"ids":IDS,"materials":descriptions,"source_us":source_us,"build_us":build_us,"install_started_us":install_started,"install_us":install_finished-install_started,"attach_us":attach_finished-install_finished,"first_draw_us":draw_finished-attach_finished,"submit_to_draw_us":draw_finished-install_started,"trace":trace,"frames":frames,"failures":failures}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ROAD_BATCH ",JSON.stringify({"source_us":source_us,"build_us":build_us,"install_us":report.install_us,"first_draw_us":report.first_draw_us,"submit_to_draw_us":report.submit_to_draw_us,"failures":failures}))
	stage.free()
	for node:Node in nodes:node.free()
	await process_frame;quit(0 if failures.is_empty() else 1)
