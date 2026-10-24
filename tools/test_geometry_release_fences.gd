extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Owners=preload("res://scripts/world3d/model_resource_owners.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func model(count:int)->RefCounted:
	var owners:=Owners.new()
	for i:int in count:
		var mesh:=Cpu.new();var surface:Array=[];surface.resize(Mesh.ARRAY_MAX)
		surface[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK]);mesh.surfaces=[surface]
		owners.visuals.append(mesh)
	return owners
func finish(service:Node)->void:
	while true:
		var done:bool=service._advance(service.pending[0],1000);service.set_process(false)
		if done:break
		await process_frame
	service._finish_front()
func run()->void:
	var receipts:={"a":0,"b":0};var a:=RefCounted.new();var b:=RefCounted.new()
	var wa:WeakRef=weakref(a);var wb:WeakRef=weakref(b)
	Retirement.defer_model_packet({"resource_owners":model(1025)},func():receipts.a+=1,a)
	Retirement.defer_model_packet({"resource_owners":model(2)},func():receipts.b+=1,b)
	a=null;b=null
	var service:Node=Retirement._service();service.set_process(false)
	await finish(service);await finish(service)
	check(service.pending.size()==3 and receipts=={"a":0,"b":0} and wa.get_ref()!=null and wb.get_ref()!=null,"bounded batches retain separate model admission fences")
	await finish(service)
	check(receipts=={"a":0,"b":0} and wa.get_ref()!=null,"first partial batch cannot release its model reservation")
	await finish(service)
	check(receipts=={"a":1,"b":0} and wa.get_ref()==null and wb.get_ref()!=null,"only the completed model returns its reservation")
	await finish(service)
	check(receipts=={"a":1,"b":1} and wb.get_ref()==null and service.known.is_empty(),"each callback runs once after its own final worker joins")
	check(service.profile.geometry_unmeasured_owners==1027 and Retirement._geometry_sizes.channels==0,"no release threshold traversal in the production fence path")
	service.free();print("GEOMETRY_RELEASE_FENCES failures=",failures);quit(1 if failures else 0)
