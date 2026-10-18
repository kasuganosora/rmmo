extends SceneTree
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
var checks:=0
var failures:=0
class Ledger extends Admission:
	var releases:=0
	func release(key:String)->void:
		releases+=1;super.release(key)
func _initialize()->void:run.call_deferred()
static func worker_result(packet:Dictionary)->Dictionary:return packet
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fixture()->Dictionary:
	var state:=GLTFState.new()
	var nodes:Array[GLTFNode]=[];var meshes:Array[GLTFMesh]=[];var watches:Array=[weakref(state)]
	var image:=Image.create(16,16,false,Image.FORMAT_RGBA8);image.fill(Color(.4,.7,.3))
	var texture:=ImageTexture.create_from_image(image)
	var material:=StandardMaterial3D.new();material.albedo_texture=texture
	watches.append(weakref(texture));watches.append(weakref(material))
	var json_nodes:Array=[]
	for i:int in 256:
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK])
		var importer:=ImporterMesh.new();importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},material)
		var mesh:=GLTFMesh.new();mesh.mesh=importer;meshes.append(mesh)
		var node:=GLTFNode.new();node.mesh=i;nodes.append(node)
		watches.append(weakref(node));watches.append(weakref(mesh));watches.append(weakref(importer));watches.append(weakref(importer.get_mesh()))
		json_nodes.append({"mesh":i,"extras":{"tags":["retire",{"payload":[i,i+1]}]}})
	state.nodes=nodes;state.meshes=meshes;state.materials=[material];state.images=[texture]
	state.buffers=[PackedByteArray([1,2,3,4])];state.json={"nodes":json_nodes}
	state.set_meta("white_materials",[material,{"shared":texture}])
	return {"state":state,"watches":watches}
func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	check(DisplayServer.get_name()!="headless","import retirement exercises actual GPU owners")
	var data:=fixture();var watches:Array=data.watches
	var author:Dictionary={"uuid":"borrowed","nested":{"keep":[1,2,3]}}
	var packet:Dictionary={"records":[author],"native_packet":{"private_preparation":{"retained_resources":[GLTFDocument.new(),data.state]}}}
	var alias:Dictionary=packet
	var ledger:=Ledger.new();ledger.reserve("import",{"estimated_bytes":1024,"exclusive":false});ledger.park("import")
	check(Retirement.defer_import_packet(packet,Callable(ledger,"release").bind("import"),ledger),"large importer donates only owned packet edges")
	data.clear();Drainer.dispose_result(packet)
	check(alias.is_empty() and author=={"uuid":"borrowed","nested":{"keep":[1,2,3]}},"packet aliases clear immediately without touching borrowed author data")
	var service:Node=root.get_node_or_null(Retirement.NODE_NAME);service.set_process(false)
	check(watches.all(func(reference):return reference.get_ref()!=null) and ledger.reserved_bytes==1024,"queued importer still owns its resources and its original byte reservation")
	for i:int in 20:service._advance(service.pending[0],1)
	check(service.pending[0].phase==0 and watches.all(func(reference):return reference.get_ref()!=null) and ledger.releases==0,"tiny capture slices keep parents and all leaf owners alive")
	service.set_process(true)
	var deadline:=Time.get_ticks_msec()+15000
	while not service.pending.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	RenderingServer.force_sync();await process_frame
	check(service.pending.is_empty() and service.known.is_empty(),"all capture and final release slices finish")
	check(watches.all(func(reference):return reference.get_ref()==null),"GLTFState, every importer/GPU mesh, node, material and texture weak probe releases")
	check(ledger.releases==1 and ledger.count()==0 and ledger.reserved_bytes==0,"admission callback runs exactly once after actual release")
	check(service.profile.imports==1 and service.profile.truncated_imports==0 and service.profile.slices>20,"nested JSON, buffers and metadata retire incrementally without truncation")
	var small:=GLTFState.new();small.nodes=[GLTFNode.new()]
	check(not Retirement.defer_import_packet({"retained_resources":[small]},Callable(ledger,"release").bind("absent"),ledger),"small state keeps the synchronous disposal path")
	check(not Retirement.defer_import_packet({"records":[data],"index":{"retained_resources":[small]}},Callable(ledger,"release").bind("absent"),ledger),"borrowed fields never enroll importer ownership")
	data=fixture()
	check(not Retirement.defer_import_packet({"records":[{"retained_resources":[data.state]}],"index":{"retained_resources":[data.state]}},Callable(ledger,"release").bind("absent"),ledger),"even a large importer inside borrowed author/index fields cannot enroll")
	data.clear()
	data=fixture();packet={"retained_resources":[data.state]};watches=data.watches;data.clear()
	var queue:=preload("res://scripts/world3d/deferred_asset_loader.gd").new();root.add_child(queue);queue.set_process(false)
	var queue_ledger:RefCounted=queue._admission
	queue_ledger.reserve("queued",{"estimated_bytes":8192,"exclusive":false})
	queue._jobs.queued={"result":packet,"token":Drainer.CancelToken.new()}
	queue._discard_job("queued")
	check(packet.is_empty() and queue._jobs.is_empty() and queue_ledger.reserved_bytes==8192 and queue_ledger.active_workers()==0,"actual queue discard clears the job while parking its original charged reservation")
	queue.free()
	while not service.pending.is_empty():await process_frame
	check(queue_ledger.reserved_bytes==0 and watches.all(func(reference):return reference.get_ref()==null),"actual queue destruction leaves its importer and ledger safely owned until retirement completes")
	data=fixture();packet={"retained_resources":[data.state]};watches=data.watches
	ledger.reserve("abandoned",{"estimated_bytes":4096,"exclusive":false})
	var token:=Drainer.CancelToken.new();token.set_meta("admission_release",Callable(ledger,"release").bind("abandoned"));token.set_meta("admission_owner",ledger)
	var worker:=Thread.new();worker.start(worker_result.bind(packet));data.clear();packet={}
	var drainer:Node=Drainer.for_tree(self);drainer.watch(worker,token);drainer.abandon(worker)
	while not drainer.jobs.is_empty():await process_frame
	check(service.pending.size()==1 and ledger.reserved_bytes==4096 and not token.has_meta("admission_owner"),"abandoned GPU worker transfers its same admission owner to sliced resource disposal")
	while not service.pending.is_empty():await process_frame
	check(ledger.releases==2 and ledger.reserved_bytes==0 and watches.all(func(reference):return reference.get_ref()==null),"abandoned worker releases its reservation only after actual importer disposal")
	# An exiting map/queue is not captured. The callback's RefCounted ledger has
	# an explicit independent owner until service exit drains the final ticket.
	data=fixture();packet={"retained_resources":[data.state]};watches=data.watches
	var detached:=Ledger.new();detached.reserve("detached",{"estimated_bytes":2048,"exclusive":false});detached.park("detached")
	var owner_watch:WeakRef=weakref(detached)
	Retirement.defer_import_packet(packet,Callable(detached,"release").bind("detached"),detached)
	data.clear();Drainer.dispose_result(packet);detached=null
	check(owner_watch.get_ref()!=null,"tree-owned ticket retains detached admission ledger")
	service.free();RenderingServer.force_sync()
	check(owner_watch.get_ref()==null and watches.all(func(reference):return reference.get_ref()==null),"tree exit drains the remaining resources and final callback without a map owner")
	print("IMPORT_STATE_RETIREMENT checks=",checks," failures=",failures);quit(1 if failures else 0)
