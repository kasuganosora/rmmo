extends SceneTree
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Owners=preload("res://scripts/world3d/model_resource_owners.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
var failures:=0
var checks:=0
class Ledger extends Admission:
	var releases:=0
	var watched:Array=[]
	var alive_on_release:=false
	func release(key:String)->void:
		alive_on_release=watched.any(func(w):return w.get_ref()!=null)
		releases+=1;super.release(key)
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
static func worker_result(packet:Dictionary)->Dictionary:return packet
func fixture(count:int=2151)->Dictionary:
	var owners:=Owners.new();var watches:Array=[]
	for i:int in count:
		var resource:=Resource.new();owners.visuals.append(resource);watches.append(weakref(resource))
		if i%3==0:owners.visuals.append(resource)
	owners.document=GLTFDocument.new();owners.state=GLTFState.new()
	owners.state.nodes=[GLTFNode.new()];owners.state.set_meta("payload",owners.visuals.slice(0,20))
	watches.append(weakref(owners.state));watches.append(weakref(owners.document))
	var author:Dictionary={"uuid":"borrowed","nested":{"keep":[1,2,3]}}
	return {"packet":{"records":[author],"resource_owners":owners},"owners":owners,"author":author,"watches":watches}
func nested_template()->Dictionary:
	var scene:=Node3D.new();var watches:Array=[]
	for i:int in 128:
		var child:=MeshInstance3D.new();child.mesh=BoxMesh.new();scene.add_child(child);child.owner=scene
		watches.append(weakref(child.mesh))
	var nested:=PackedScene.new();nested.pack(scene);scene.free();watches.append(weakref(nested))
	scene=Node3D.new();scene.set_meta("nested_template",nested)
	var owners:=Owners.new();owners.packed=PackedScene.new();owners.packed.pack(scene);scene.free()
	watches.append(weakref(owners.packed))
	return {"packet":{"resource_owners":owners},"watches":watches}
func drain(service:Node)->void:
	var count:=0
	while not service.pending.is_empty() and count<500000:
		if service._advance(service.pending[0],1):service._finish_front()
		count+=1
	check(count<500000,"bounded typed cursor completes")
func run()->void:
	var data:=fixture();var packet:Dictionary=data.packet;var owners:RefCounted=data.owners;var author:Dictionary=data.author;var watches:Array=data.watches;data.clear()
	var ledger:=Ledger.new();ledger.reserve("large",{"estimated_bytes":8192,"exclusive":false})
	check(Retirement.defer_model_packet(packet,Callable(ledger,"release").bind("large"),ledger),"typed owner transfers directly without graph discovery")
	Drainer.dispose_result(packet)
	var service:Node=root.get_node(Retirement.NODE_NAME);service.set_process(false)
	check(packet.is_empty() and not owners.visuals.is_empty() and ledger.reserved_bytes==8192,"outer aliases clear while deferred leaves keep charged reservation")
	check(watches.all(func(w):return w.get_ref()!=null),"every resource remains owned until retirement starts")
	service._advance(service.pending[0],1)
	check(ledger.releases==0 and not service.pending.is_empty(),"tiny slice cannot release admission early")
	drain(service)
	check(owners.visuals.is_empty() and owners.state==null and owners.document==null and watches.all(func(w):return w.get_ref()==null),"all repeated visual references and importer owners release")
	check(author=={"uuid":"borrowed","nested":{"keep":[1,2,3]}},"borrowed author graph remains untouched")
	check(ledger.releases==1 and ledger.reserved_bytes==0 and service.known.is_empty(),"reservation releases exactly once after every owner")
	check(service.profile.model_slices>20 and service.profile.imports==1,"visuals and importer work span bounded slices")
	check(not Retirement.defer_model_packet({"records":[{"resource_owners":Owners.new()}]},Callable(),null),"borrowed fields never enroll")
	check(not Retirement.defer_model_packet({"retained_resources":[Resource.new()]},Callable(),null),"typed handoff has no legacy packet adapter")
	data=fixture();packet=data.packet;watches=data.watches;owners=data.owners;data.clear()
	var queue:=preload("res://scripts/world3d/deferred_asset_loader.gd").new();root.add_child(queue);queue.set_process(false)
	var queue_ledger:RefCounted=queue._admission;queue_ledger.reserve("queued",{"estimated_bytes":4096,"exclusive":false})
	queue._jobs.queued={"result":packet,"token":Drainer.CancelToken.new()};queue._discard_job("queued")
	check(packet.is_empty() and queue._jobs.is_empty() and queue_ledger.reserved_bytes==4096,"actual discard clears job and retains admission")
	queue.free();service.free()
	check(queue_ledger.reserved_bytes==0 and owners.visuals.is_empty() and watches.all(func(w):return w.get_ref()==null),"tree exit drains detached map resources and callback")
	data=fixture();packet=data.packet;watches=data.watches;owners=data.owners;data.clear()
	ledger.reserve("abandoned",{"estimated_bytes":4096,"exclusive":false})
	var token:=Drainer.CancelToken.new();token.set_meta("admission_release",Callable(ledger,"release").bind("abandoned"));token.set_meta("admission_owner",ledger)
	var worker:=Thread.new();worker.start(worker_result.bind(packet));packet={}
	var drainer:Node=Drainer.for_tree(self);drainer.watch(worker,token);drainer.abandon(worker)
	while not drainer.jobs.is_empty():await process_frame
	check(ledger.reserved_bytes==4096 and not token.has_meta("admission_owner"),"abandoned worker transfers its independent ledger")
	service=root.get_node(Retirement.NODE_NAME);service.set_process(false);drain(service)
	check(ledger.reserved_bytes==0 and ledger.releases==2 and watches.all(func(w):return w.get_ref()==null),"abandoned worker releases every owner before callback")
	data=fixture(1);packet=data.packet;watches=data.watches;data.clear();Drainer.dispose_result(packet)
	check(packet.is_empty() and watches.all(func(w):return w.get_ref()==null),"synchronous shutdown path also understands typed ownership")
	data=nested_template();packet=data.packet;watches=data.watches;data.clear()
	ledger.watched=watches;ledger.reserve("nested",{"estimated_bytes":8192,"exclusive":false})
	Retirement.defer_model_packet(packet,Callable(ledger,"release").bind("nested"),ledger);Drainer.dispose_result(packet)
	drain(service)
	check(not ledger.alive_on_release and watches.all(func(w):return w.get_ref()==null),"nested PackedScene dependencies release before admission callback")
	print("OWNED_PACKET_RETIREMENT checks=",checks," failures=",failures);quit(1 if failures else 0)
