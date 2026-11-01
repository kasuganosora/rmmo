extends SceneTree
## Real MapLoader exit, mixed cooked owners and CPU-only source/context data.
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Snapshot=preload("res://scripts/world3d/document_source_snapshot.gd")
const Terrain=preload("res://scripts/world3d/terrain_neighbors.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
var checks:=0
var failures:Array[String]=[]
var output:=""
var entries:=128
class MeshOwner extends ArrayMesh:
	var receipt:Dictionary
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:receipt.thread=OS.get_thread_caller_id();receipt.count+=1
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func payload()->Array:
	var row:Array=[]
	for i in 2048:row.append(float(i))
	var rows:Array=[]
	for i in entries:rows.append({"id":str(i),"heights":row})
	# Match decoded cache/source ownership, not repeated aliases of one array.
	return bytes_to_var(var_to_bytes(rows))
func fixture(borrowed:bool)->Dictionary:
	var receipt:={"thread":0,"count":0}
	var mesh:=MeshOwner.new();mesh.receipt=receipt
	var cache:={"entries":payload(),"meshes":[],"materials":[],"_restored_meshes":[mesh]}
	var snapshot:=Snapshot.new()
	# JSON parser is the production source's CPU-only data boundary.
	snapshot._data=JSON.parse_string(JSON.stringify({"nodes":payload()}));snapshot._bytes=PackedByteArray([1,2,3])
	snapshot.error="";snapshot._retained=true;snapshot._signature="test-source"
	var context:=Terrain.new()
	var image:=Image.create(32,32,false,Image.FORMAT_RF)
	context.data={"terrain":{"signature":payload(),"normals":{0:Vector3.UP},"neighbors":[],"image":image,"padding":Vector2.ONE}}
	context.signature=[["terrain"]];context.edge_cache={"terrain":{"edges":[],"signature":[1,2,3]}}
	context.point_index={Vector3i.ZERO:[{"id":"terrain","at":0,"n":Vector3.UP}]};context.dependents={"terrain":[]}
	var loader:=Loader.new();root.add_child(loader);loader.set_process(false)
	loader._mesh_cache_data=cache;loader._source_snapshot=snapshot;loader._terrain_context=context
	return {"loader":loader,"receipt":receipt,"mesh":weakref(mesh),"image":weakref(image),"snapshot_ref":weakref(snapshot),"context_ref":weakref(context),"borrowed":{ "cache":cache,"snapshot":snapshot,"context":context} if borrowed else {}}
func cpu_only(value:Variant)->bool:
	if value is Object or value is RID or value is Callable or value is Signal:return false
	if value is Dictionary:
		for key:Variant in value:
			if not cpu_only(key) or not cpu_only(value[key]):return false
	elif value is Array:
		for item:Variant in value:
			if not cpu_only(item):return false
	return true
func drain(service:Node)->Dictionary:
	var calls:=0;var elapsed:=0;var maximum:=0;var start:=Time.get_ticks_usec()
	while is_instance_valid(service) and not service.pending.is_empty():
		var began:=Time.get_ticks_usec();service._process(0.);service.set_process(false)
		var cost:=Time.get_ticks_usec()-began;elapsed+=cost;maximum=maxi(maximum,cost);calls+=1
		await process_frame
		if Time.get_ticks_usec()-start>15000000:check(false,"retirement finishes within component timeout");break
	return {"calls":calls,"main_us":elapsed,"max_main_us":maximum,"wall_us":Time.get_ticks_usec()-start}
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--entries="):entries=arg.trim_prefix("--entries=").to_int()
	preload("res://scripts/world3d/frame_work_budget.gd").enabled=false
	var f:=fixture(false)
	# Closing before the deferred setup frame must safely use native destruction.
	f.loader.free()
	check(f.mesh.get_ref()==null and f.image.get_ref()==null,"immediate close does not create a service inside locked exit propagation")
	await process_frame
	var unused:Node=root.get_node_or_null(Retirement.NODE_NAME)
	check(unused!=null and not unused.is_processing(),"prepared empty service remains idle until an owner is donated")
	if unused!=null:unused.free()
	f=fixture(false);await process_frame
	var began:=Time.get_ticks_usec();f.loader.free();var exit_us:=Time.get_ticks_usec()-began
	var service:Node=root.get_node_or_null(Retirement.NODE_NAME)
	check(service!=null and not service.pending.is_empty(),"loader exit transfers final decoded owners to the existing service")
	check(f.mesh.get_ref()!=null and f.image.get_ref()!=null,"Mesh and Image final owners survive the synchronous exit")
	check(f.snapshot_ref.get_ref()==null and f.context_ref.get_ref()==null,"source and terrain wrappers are not retained to hide their destruction")
	var cpu_tickets:=0;var schema_ok:=true
	if service!=null:
		service.set_process(false)
		for ticket:Dictionary in service.pending:
			if ticket.get("kind","")=="cpu_geometry":cpu_tickets+=1;schema_ok=schema_ok and cpu_only(ticket.values)
	check(cpu_tickets>=3 and schema_ok,"cache, source and terrain transfer only CPU values, never native objects")
	var timing:Dictionary=await drain(service)
	check(f.mesh.get_ref()==null and f.image.get_ref()==null and f.receipt.count==1 and f.receipt.thread==OS.get_main_thread_id(),"native resources die once on MAIN after sliced retirement")
	check(service!=null and int(service.profile.get("geometry_last_thread_id",OS.get_main_thread_id()))!=OS.get_main_thread_id(),"actual decoded final releases run on CPU workers")
	var profile:Dictionary=service.profile.duplicate(true) if service!=null else {}
	if service!=null:service.free()
	f=fixture(true);await process_frame;f.loader.free();service=root.get_node_or_null(Retirement.NODE_NAME)
	if service!=null:service.set_process(false)
	await drain(service)
	check(f.borrowed.cache.entries.size()==entries and f.borrowed.cache.entries[0].heights[2047]==2047.0 and f.borrowed.cache._restored_meshes.size()==1,"external cooked cache aliases retain their bytes and native owners")
	check(f.borrowed.snapshot._data.nodes.size()==entries and f.borrowed.snapshot._bytes.size()==3 and f.borrowed.context.data.terrain.image.get_width()==32,"shared snapshot/context wrappers remain usable after loader disposal")
	check(f.mesh.get_ref()!=null and f.image.get_ref()!=null,"retirement never destroys a live external borrower")
	f.borrowed.clear()
	# The final shared wrapper must also donate its CPU fields at actual deletion.
	service=root.get_node_or_null(Retirement.NODE_NAME)
	if service!=null:service.set_process(false)
	await drain(service)
	check(f.mesh.get_ref()==null and f.image.get_ref()==null,"late borrowers release without a permanent owner leak")
	if service!=null:service.free()
	Retirement.background_decoded_release_enabled=false
	f=fixture(false);await process_frame;f.loader.free();service=root.get_node_or_null(Retirement.NODE_NAME)
	if service!=null:service.set_process(false)
	var cpu_when_disabled:=0
	if service!=null:
		for ticket:Dictionary in service.pending:cpu_when_disabled+=int(ticket.get("kind","")=="cpu_geometry")
	await drain(service)
	check(cpu_when_disabled==0 and f.mesh.get_ref()==null and f.image.get_ref()==null,"disabled CPU retirement preserves synchronous ownership fallback")
	if service!=null:service.free()
	Retirement.background_decoded_release_enabled=true
	var report:={"checks":checks,"failures":failures,"entries":entries,"exit_us":exit_us,"retirement":timing,"profile":profile,"scope":"loader member lifetimes and CPU handoff; not a map performance score"}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("LOADER_DATA_RETIREMENT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
