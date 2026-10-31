extends SceneTree
## Isolate one ranked map record without changing authored geometry or materials.
## Timings include call return/destruction, which inner _mesh fields can omit.
const ROOT="D:/code/rmmo_runtime"
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Road=preload("res://scripts/world3d/native_road_preparation.gd")
const Bounds=preload("res://scripts/world3d/procedural_surface_bounds.gd")
const Paint=preload("res://scripts/world3d/surface_paint_preparation.gd")
const Textures=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Publication=preload("res://scripts/world3d/material_publication.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Materials=preload("res://scripts/world3d/surface_materials.gd")
var failures:Array=[]
var units:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func measured(label:String,began:int,iteration:int,details:Dictionary={})->void:
	units.append({"stage":label,"start_us":began,"duration_us":Time.get_ticks_usec()-began,"iteration":iteration,"details":details})
static func prepare(record:Dictionary,plan:Dictionary)->Dictionary:
	var budget:=Road.estimate(record,true)
	var road:=Road.prepare(record,null,true,ROOT,budget)
	if not road.error.is_empty():return road
	road.bounds=Bounds.bounds(road.arrays)
	road.paint=Paint.for_road(record,road.arrays,budget,null,road.bounds)
	road.textures=Textures.prepare(Textures.sources(record),plan,ROOT,null,true,{},true)
	road.error=road.textures.error
	return road
func run()->void:
	var output:="";var map_path:="";var uuid:="pavement_28cfb38d30df3a942dcd";var resident_only:=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.substr(9).replace("\\","/")
		elif arg.begins_with("--map="):map_path=arg.substr(6).replace("\\","/")
		elif arg.begins_with("--uuid="):uuid=arg.substr(7)
		elif arg=="--resident-only":resident_only=true
	if not output.begins_with(ROOT+"/review_artifacts/") or not map_path.begins_with(ROOT+"/review_artifacts/"):quit(2);return
	check(DisplayServer.get_name()!="headless","actual GPU on private desktop")
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);root.size=Vector2i(512,512)
	var map_sha:=FileAccess.get_sha256(map_path)
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(map_path));var compact:Dictionary={}
	for node:Dictionary in raw.nodes:
		for row:Dictionary in node.get("extras",{}).get("rmmo_records",[]):
			if row.uuid==uuid:compact=row;break
	check(not compact.is_empty(),"ranked UUID exists in frozen map")
	if compact.is_empty():quit(1);return
	var decoded:=Store.read_records([compact],map_path,ROOT,null,1,true)
	check(decoded.ok and decoded.records.size()==1,"exact record hydrates without map writes")
	if not decoded.ok:quit(1);return
	var record:Dictionary=decoded.records[0]
	check(record.has("road_mesh"),"ranked object is an authored road")
	if not record.has("road_mesh"):quit(1);return
	var plan:=Textures.estimate(Textures.sources(record),ROOT)
	Trace.minimum_event_us=0;Trace.start()
	var worker:=Thread.new();var began:=Time.get_ticks_usec()
	check(worker.start(prepare.bind(record,plan))==OK,"real geometry and texture worker starts")
	while worker.is_alive():await process_frame
	var packet:Dictionary=worker.wait_to_finish();measured("worker_prepare",began,-1)
	check(packet.get("error","missing").is_empty(),"real geometry and texture preparation succeeds")
	if not packet.get("error","missing").is_empty():print(packet.error);quit(1);return
	preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
	if resident_only:
		# Model the shared pool's already-resident handoff without first opening
		# the editor's image installation helper. Keep actual GPU owners/tickets.
		var previous_images:Dictionary=Materials.prepared_images
		var previous_textures:Dictionary=Materials.prepared_textures
		Materials.prepared_images=packet.textures.get("images",{}).duplicate()
		Materials.prepared_textures=packet.textures.get("uploaded_textures",{})
		var resident:Dictionary={}
		for definition:Dictionary in Materials.definitions(record):
			for field:String in Materials.MAP_FIELDS:
				var key:=Materials.definition_texture_key(definition,field)
				if key.is_empty() or resident.has(key):continue
				var texture:=Materials.texture(definition,field)
				check(texture!=null,"real resident texture "+key)
				if texture!=null:resident[key]={"texture":texture,"source_sha":packet.textures.sources.get(Materials.texture_source_path(key),"")}
		Materials.prepared_images=previous_images;Materials.prepared_textures=previous_textures
		packet.textures={"images":{},"uploaded_textures":{},"resident_textures":resident,"sources":packet.textures.sources}
	var doc:=preload("res://scripts/world3d/world_document.gd").new()
	doc.load_immutable_records=true;doc.load_require_native_products=true
	doc.load_paint_validation={};doc.load_texture_checks={};doc.load_material_pool={}
	doc.load_surface_arrays[uuid]=packet.arrays;doc.load_surface_bounds[uuid]=packet.bounds
	if packet.paint.get("ok",false):doc.load_surface_paints[uuid]=packet.paint
	var owners:Dictionary={};var state:Dictionary={};var iterations:Array=[];var helper_cache_states:Array=[]
	var helper_cached:=ResourceLoader.has_cached("res://scripts/world_editor/terrain_texture_preparation.gd")
	for iteration:int in 3:
		var phase:=Publication.PROGRESS
		while phase==Publication.PROGRESS:
			began=Time.get_ticks_usec()
			phase=Publication.step_record_prepared(record,doc.load_paint_validation,owners,packet.textures,state)
			measured("record_texture",began,iteration,{"result":phase})
			if phase==Publication.PROGRESS:await process_frame
		check(phase==Publication.READY,"record textures complete iteration="+str(iteration))
		if phase!=Publication.READY:break
		began=Time.get_ticks_usec();var scope:=Publication.begin_record_scope(record,packet.textures,owners,state)
		measured("scope_begin",began,iteration)
		check(scope.ok,"ordinary publication scope opens")
		if not scope.ok:break
		var parts:Dictionary={}
		began=Time.get_ticks_usec();var holder:MeshInstance3D=doc._mesh(record,true,parts)
		measured("mesh_call_with_return",began,iteration,parts)
		began=Time.get_ticks_usec();Publication.end_record_scope(scope);measured("scope_end",began,iteration)
		helper_cache_states.append(ResourceLoader.has_cached("res://scripts/world_editor/terrain_texture_preparation.gd"))
		check(not holder.has_meta("paint_error") and holder.mesh is Cpu,"prepared CPU geometry preserves real materials")
		var cursor:=preload("res://scripts/world3d/instance_spec_preparation.gd").new()
		began=Time.get_ticks_usec();cursor.begin(holder,false,0);measured("spec_begin",began,iteration)
		var ready:=false
		while not ready:
			began=Time.get_ticks_usec();ready=cursor.advance(2000);measured("spec_advance",began,iteration)
			if not ready:await process_frame
		check(not is_instance_valid(holder) and cursor.specs.size()==1 and cursor.specs[0].uuid==uuid,"exact road projects once and private graph is freed")
		iterations.append(cursor.profile.duplicate())
		cursor.specs.clear();await process_frame
	var trace:=Trace.stop()
	owners.clear();state.clear();packet.clear();doc=null
	preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
	check(FileAccess.get_sha256(map_path)==map_sha,"frozen map unchanged")
	units.sort_custom(func(a,b):return a.duration_us>b.duration_us)
	var report:={"map_sha":map_sha,"uuid":uuid,"record":record,"units":units,"iterations":iterations,"trace":trace,"failures":failures,"resident_only":resident_only,"helper_cached_before":helper_cached,"helper_cached_after_scope":helper_cache_states,"scope":"One actual record, its prepared textures and geometry; no other town jobs. CPU projection/private disposal only, not full-map performance or a draw-equivalence test."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("RANKED_ROAD_LIFECYCLE ",JSON.stringify({"slowest":units.slice(0,10),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
