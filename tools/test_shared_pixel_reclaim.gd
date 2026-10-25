extends SceneTree
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var passed:=0
var failed:=0
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failed+=1
func _initialize()->void:
	var path:="mounted/test.png"
	var row:Dictionary={"path":path,"width":2048,"height":2048,"source_bytes":1048576,"output_bytes":22369620,"extension":"png","cache_limit":44804776}
	var plan:Dictionary={"rows":{path:row}}
	var ledger:=Admission.new();ledger.worker_limit=4;ledger.byte_limit=1024*1024*1024
	var pool:=Pool.new();pool.admission=ledger
	var original:=pool.offer(plan)
	check(ledger.reserve_bundle("original",{"estimated_bytes":original.scratch_bytes,"exclusive":false},original.retained),"original producer reserves workspace and one shared output")
	pool.commit("original",original)
	var follower:=pool.offer(plan)
	ledger.reserve_bundle("follower",{"estimated_bytes":follower.scratch_bytes,"exclusive":false},follower.retained);pool.commit("follower",follower);ledger.park("follower")
	pool.cancel("original") # Keep original physically alive, including its lease.
	var retry:=pool.offer(plan,{}, {path:path.sha256_text()})
	check(retry.bindings==original.bindings,"trusted retry and first observation bind the same immutable source")
	check(retry.leaders.size()==1 and retry.retained.is_empty(),"failed producer transfers leadership without duplicating its output charge")
	check(retry.scratch_bytes>=Prep.workspace_bytes(row),"replacement reserves complete decoder scratch before starting")
	if retry.bindings==original.bindings and retry.leaders.size()==1 and retry.retained.is_empty():
		var before:int=ledger.reserved_bytes
		check(ledger.reserve_bundle("retry",{"estimated_bytes":retry.scratch_bytes,"exclusive":false},retry.retained),"replacement is admitted while cancelled producer still owns its workspace")
		pool.commit("retry",retry)
		check(ledger.reserved_bytes==before+retry.scratch_bytes,"handoff adds only a new active workspace")
		var image:=Image.create(4,4,false,Image.FORMAT_RGBA8)
		check(not pool.publish("original",path,path.sha256_text(),image),"cancelled producer cannot publish late into replacement ownership")
		check(pool.publish("retry",path,path.sha256_text(),image),"replacement publishes the single shared image")
		var fetched:=pool.fetch("follower",path,path.sha256_text(),null)
		check(fetched.get("image")==image and pool.snapshot().produced==1,"existing follower consumes the replacement image without rebinding")
		var fresh:=pool.offer(plan)
		check(fresh.bindings==retry.bindings and fresh.leaders.is_empty() and fresh.retained.is_empty(),"new consumer reuses the same replacement despite having no retry revision")
		var generation:=Paint.source_generation;Paint.source_generation+=1
		check(pool.offer(plan).bindings!=retry.bindings,"explicit source refresh starts a separate image generation")
		Paint.source_generation=generation
		ledger.park("original");pool.release("original");ledger.release("original")
		check(pool.fetch("follower",path,path.sha256_text(),null).get("image")==image,"old owner retirement cannot poison or release its replacement")
		ledger.park("retry");pool.release("retry");ledger.release("retry")
	else:
		ledger.park("original");pool.release("original");ledger.release("original")
	pool.release("follower");ledger.release("follower")
	check(ledger.reserved_bytes==0 and pool.snapshot().outputs==0,"last consumer releases every retained charge")
	Prep.Pixels.Policy.verify_packages=true
	check(pool.offer(plan,{}, {path:"a"}).bindings!=pool.offer(plan,{}, {path:"b"}).bindings,"strict mutable-source diagnostics keep distinct revisions")
	Prep.Pixels.Policy.verify_packages=false
	print("SHARED_PIXEL_RECLAIM passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
