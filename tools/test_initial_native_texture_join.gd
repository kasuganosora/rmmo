extends SceneTree
## Initial coordinator contract. Fixtures and native table metadata stay outside
## the project; the reader injection owns every PackedScene until main cleanup.
const Preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
const Binding=preload("res://scripts/world3d/model_texture_bindings.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Readiness=preload("res://scripts/world3d/model_texture_readiness.gd")
const Shared=preload("res://scripts/world3d/shared_prefab_images.gd")
const ID="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
var failures:Array[String]=[]
var checks:=0
var content_root:String
var packed:PackedScene
var material:StandardMaterial3D
var candidate:Dictionary
var fixtures:Dictionary={}
var geometry_reads:=0
var counter_mutex:=Mutex.new()

class TextureStub extends Texture2D:
	func _get_width()->int:return 4
	func _get_height()->int:return 4
class ControlledPool extends Shared:
	var gate:=Semaphore.new()
	var mutex:=Mutex.new()
	var hold:=false
	var entered:=false
	var fail:=false
	func _streamed_handoff_enabled()->bool:return true
	func _streamed_handoff_texture_valid(texture:Texture2D)->bool:return texture is TextureStub
	func _load_stream(_plan:Dictionary,_digest:String)->Texture2D:
		mutex.lock();entered=true;var wait_here:=hold;mutex.unlock()
		if wait_here:gate.wait()
		return null if fail else TextureStub.new()
	func is_entered()->bool:
		mutex.lock();var result:=entered;mutex.unlock();return result

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func make_fixture(empty:bool=false)->void:
	content_root=Paths.external_root().path_join("initial_native_join_%d"%OS.get_process_id())
	var directory:=content_root.path_join("cache/world3d/compiled_assets_v1/texture_tables_v1")
	DirAccess.make_dir_recursive_absolute(directory)
	var table:={"version":1,"textures":{ID:{"file":"cache/world3d/model_textures_v1/"+ID+".stex","pixel_sha":ID,"width":4,"height":4,"format":Image.FORMAT_RGBA8,"mip_sizes":[64],"bytes":64,"file_bytes":116,"alpha":false,"normal_xy":false}},"image_bytes":64}
	if empty:table.textures={};table.image_bytes=0
	var encoded:=JSON.stringify(table);var sha:=encoded.sha256_text()
	var file:=FileAccess.open(directory.path_join(sha+".json"),FileAccess.WRITE);file.store_string(encoded);file.close()
	var scene:=Node3D.new();scene.set_meta(Binding.TABLE_META,sha)
	var part:=MeshInstance3D.new();scene.add_child(part);part.owner=scene
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	material=StandardMaterial3D.new()
	if not empty:material.set_meta(Binding.BINDINGS_META,{"albedo_texture":{"id":ID,"normal":false}})
	mesh.surface_set_material(0,material);part.mesh=mesh
	packed=PackedScene.new();check(packed.pack(scene)==OK,"pack image-free initial fixture");scene.free()
	candidate={"estimated_bytes":4096,"exclusive":false,"source_sha":"b".repeat(64),"texture_table":{"version":1,"sha256":sha,"bytes":encoded.to_utf8_buffer().size(),"textures":0 if empty else 1,"image_bytes":0 if empty else 64}}

func run()->void:
	make_fixture()
	await joined_case("shared",2,false,false,false)
	await joined_case("cancel",2,true,false,false)
	await joined_case("missing",2,false,true,false)
	await joined_case("geometry-failure",2,false,false,false)
	await joined_case("serial-fallback",1,false,false,true)
	await joined_case("oversize",2,false,false,false,1024)
	make_fixture(true)
	await joined_case("empty",2,false,false,false)
	print("INITIAL_NATIVE_TEXTURE_JOIN ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func read_candidate(path:String,_candidate:Dictionary)->Dictionary:
	counter_mutex.lock();geometry_reads+=1;counter_mutex.unlock()
	if path.ends_with("geometry-failure_other.glb"):return {"error":ERR_INVALID_DATA,"error_message":"injected geometry failure","packed":fixtures[path].packed}
	return {"error":OK,"compiled":true,"packed":fixtures[path].packed,"source_digest":"b".repeat(64)}

func fake_pixels(plan:Dictionary,_root:String,token:RefCounted,shared:Dictionary)->Dictionary:
	var textures:Dictionary={};var waiting:=false
	for key:String in plan.plan.rows:
		if token.is_cancelled():return {"error":"cancelled","cancelled":true}
		var row:Dictionary=plan.plan.rows[key];var digest:String=row.path.sha256_text()
		if not shared.pool.remember_source_identity(shared.consumer,row.path,digest):return {"error":"identity"}
		if shared.leaders.has(key) and not shared.pool.load_stream(shared.consumer,key,digest,row):return {"error":"missing product"}
		var fetched:Dictionary=shared.pool.fetch(shared.consumer,key,digest,token)
		if not fetched.error.is_empty():return fetched
		if fetched.get("pending",false):waiting=true
		else:textures[key]=fetched.texture
	return {"error":"","waiting_pixels":waiting,"uploaded_textures":textures,"images":{}}

func joined_case(label:String,workers:int,cancelled:bool,missing:bool,synchronous:bool,limit:int=4*1024*1024*1024)->void:
	var path:=content_root.path_join(label+".glb")
	var second:=content_root.path_join(label+"_other.glb")
	var copy:=packed.duplicate(true) as PackedScene
	fixtures={path:{"packed":packed},second:{"packed":copy}};geometry_reads=0
	var prep:=Preparation.new();prep.require_native_products=true
	var pool:=ControlledPool.new();pool.hold=label in ["shared","cancel","geometry-failure"];pool.fail=missing
	prep.native_texture_pool=pool;prep.native_texture_preparer=fake_pixels;prep.inflight_byte_limit=limit
	prep.memory_estimator=func(_path:String)->Dictionary:return {"estimated_bytes":4096,"exclusive":false}
	prep.candidate_provider=func(_path:String)->Dictionary:return candidate
	prep.candidate_reader=read_candidate
	var starter:Callable=(func(_thread:Thread,_call:Callable)->int:return ERR_CANT_CREATE) if synchronous else Callable()
	var worker:=Thread.new();check(worker.start(prep.run.bind([path,second,path],Callable(),workers,starter,content_root))==OK,label+": initial coordinator starts off main")
	var deadline:=Time.get_ticks_msec()+10000;var released:=not pool.hold
	while worker.is_alive() and Time.get_ticks_msec()<deadline:
		counter_mutex.lock();var reads:=geometry_reads;counter_mutex.unlock()
		if not released and pool.is_entered() and reads==2:
			check(true,label+": held pixel producer does not block the other geometry worker")
			if cancelled:prep.cancel()
			pool.gate.post();released=true
		await process_frame
	if worker.is_alive():
		check(false,label+": initial coordinator finishes without admission deadlock")
		prep.cancel()
		if not released:pool.gate.post()
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish()
	var failed:bool=cancelled or missing or label=="geometry-failure"
	check((result.error!=OK)==failed,label+": result preserves success/cancellation/failure")
	check(result.threads_started==result.threads_joined,label+": all owned workers joined")
	check(result.get("native_texture_profile",{}).get("unique_products",0)==(0 if label=="empty" else 1),label+": unique products counted across duplicate paths and two native models")
	check(result.native_texture_profile.worker_slots_peak<=workers,label+": common worker cap respected")
	check(geometry_reads>=1 and geometry_reads<=2 if missing else geometry_reads==2,label+": failed work stops dispatch without duplicate model reads" if missing else label+": model path deduplication remains exact")
	if label=="geometry-failure":check(result.error==ERR_INVALID_DATA and result.error_message=="injected geometry failure",label+": sibling cancellation cannot conceal the real failure")
	if not failed:
		check(material.albedo_texture==null if label=="empty" else material.albedo_texture!=null,label+": authored texture state present before publication")
		check(Readiness.packed_ready(packed) and Readiness.packed_ready(copy),label+": both real native templates have runtime completion proof")
		check(pool.snapshot().get("streamed_loads",0)==(0 if label=="empty" else 1),label+": shared texture load count is exact")
		check(result.inflight_reserved_at_return==0,label+": complete outputs transfer out of transient admission")
	if synchronous:check(result.threads_started==0 and result.fallback_count>0,label+": thread-start failure retains charged synchronous route")
	var scope:RefCounted=result.native_texture_scope;var ledger:RefCounted=pool.admission
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(result)
	check(scope.released and pool.snapshot().consumers==0 and ledger.count()==0,label+": main drainer releases operation scope, consumers and all reservations")
	scope.release_now();check(ledger.count()==0,label+": repeated scope retirement is harmless")
	fixtures.clear();copy=null
	material.albedo_texture=null
	if packed.has_meta(Readiness.READY_META):packed.remove_meta(Readiness.READY_META)
