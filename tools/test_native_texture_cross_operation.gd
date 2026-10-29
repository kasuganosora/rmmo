extends SceneTree
const InitialFixture=preload("res://tools/test_initial_native_texture_join.gd")
const QueueFixture=preload("res://tools/test_deferred_native_texture_join.gd")
const Initial=preload("res://scripts/world3d/model_parse_preparation.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
class Pool extends InitialFixture.ControlledPool:
	func _streamed_handoff_texture_valid(texture:Texture2D)->bool:return texture.is_class("StreamedTexture2D")
	func _load_stream(row:Dictionary,digest:String)->Texture2D:
		# Real native type/identity, without file loading or a real renderer.
		var texture:Texture2D=ClassDB.instantiate("StreamedTexture2D")
		texture.set_meta("runtime_source_sha256",digest);texture.set_meta("runtime_texture_representation",row.representation)
		return texture
class Fixture extends InitialFixture:
	func fake_pixels(plan:Dictionary,_root:String,token:RefCounted,shared:Dictionary)->Dictionary:
		var textures:Dictionary={};var sources:Dictionary={};var waiting:=false
		for key:String in plan.plan.rows:
			var row:Dictionary=plan.plan.rows[key];var digest:String=row.path.sha256_text();sources[row.path]=digest
			if not shared.pool.remember_source_identity(shared.consumer,row.path,digest):return {"error":"identity"}
			if shared.cached.has(key):continue
			if shared.leaders.has(key) and not shared.pool.load_stream(shared.consumer,key,digest,row):return {"error":"producer"}
			var fetched:Dictionary=shared.pool.fetch(shared.consumer,key,digest,token)
			if not fetched.error.is_empty():return fetched
			if fetched.get("pending",false):waiting=true
			else:textures[key]=fetched.texture
		return {"error":"","waiting_pixels":waiting,"uploaded_textures":textures,"images":{},"sources":sources}
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func _initialize()->void:run.call_deferred()
func identity(packed:PackedScene)->Dictionary:
	var scene:=packed.instantiate();var texture:Texture2D=scene.get_child(0).mesh.surface_get_material(0).albedo_texture
	var value:={"id":texture.get_instance_id(),"weak":weakref(texture)};scene.free();return value
func run()->void:
	Paint.refresh_sources()
	var fixture:=Fixture.new();fixture.make_fixture()
	var blank:PackedScene=fixture.packed.duplicate(true)
	var a:=fixture.content_root.path_join("initial.glb");var b:=fixture.content_root.path_join("deferred.glb")
	var prep:=Initial.new();var pool:=Pool.new();prep.native_texture_pool=pool;prep.native_texture_preparer=fixture.fake_pixels;prep.require_native_products=true
	prep.memory_estimator=func(_path:String)->Dictionary:return {"estimated_bytes":4096,"exclusive":false}
	prep.candidate_provider=func(_path:String)->Dictionary:return fixture.candidate
	prep.candidate_reader=func(_path:String,_candidate:Dictionary)->Dictionary:return {"error":OK,"compiled":true,"packed":fixture.packed,"source_digest":fixture.candidate.source_sha}
	var thread:=Thread.new();thread.start(prep.run.bind([a],Callable(),2,Callable(),fixture.content_root))
	while thread.is_alive():await process_frame
	var prepared:Dictionary=thread.wait_to_finish();check(prepared.error==OK,"initial native model completes")
	check(Assets.cache_packed(a,prepared.entries[0].packed,fixture.candidate.source_sha),"initial cache owns the completed model")
	var first:=identity(Assets._scenes[a]);var plan:Dictionary=InitialFixture.Binding.candidate_plan(fixture.candidate,fixture.content_root,{})
	var key:String=plan.plan.rows.keys()[0]
	var loader:=Loader.new();loader._native_texture_scope=prepared.native_texture_scope
	loader._cancelled=true
	if loader.has_method("_publish_initial_native_textures"):loader.call("_publish_initial_native_textures")
	check(Paint.retained_texture(key)==null,"cancelled initial publication never exposes prepared owners")
	loader._cancelled=false
	if prepared.native_texture_scope.has_method("publish_ready"):
		prepared.native_texture_scope.completed_success=false;loader.call("_publish_initial_native_textures")
		check(Paint.retained_texture(key)==null,"failed initial transaction does not advertise successful sibling owners")
		prepared.native_texture_scope.completed_success=true
	if loader.has_method("_publish_initial_native_textures"):loader.call("_publish_initial_native_textures")
	check(Paint.retained_texture(key)!=null,"initial main publication advertises its completed native owner")
	loader._native_texture_scope=null;loader.free()
	Drainer.dispose_result(prepared);fixture.packed=null;fixture.material=null
	check(pool.snapshot().outputs==0 and first.weak.get_ref()!=null,"initial scope retires while the cached model keeps its texture alive")
	var tickets:Dictionary=Prefab.texture_tickets(plan.plan.rows)
	check(tickets.has(key) and tickets[key].texture.get_instance_id()==first.id,"new operation finds the exact initial texture through a weak ticket")
	Paint.residency_budget_enabled=false
	var unbudgeted:Dictionary=Prefab.texture_tickets(plan.plan.rows)
	check(unbudgeted.has(key) and unbudgeted[key].texture.get_instance_id()==first.id,"native weak reuse survives disabling the legacy Paint cache budget")
	unbudgeted.clear();Paint.residency_budget_enabled=true
	check(Paint._textures.is_empty(),"native sharing adds no strong hot-cache residency")
	tickets.clear()
	var queue:=QueueFixture.Queue.new();queue.fixture=fixture;queue.require_native_products=true;queue.loading_worker_limit=2;queue._reference_root=fixture.content_root
	var second_pool:=Pool.new();queue._shared_images=second_pool;queue.copies[b]=blank;blank=null
	var box:=AABB(Vector3.ZERO,Vector3.ONE)
	queue.pending.append({"record":{"uuid":"cross_operation","collision":"none"},"path":b,"bounds":box,"digest":fixture.candidate.source_sha,"memory":{"estimated_bytes":4096,"exclusive":false,"known":true}})
	check(queue.begin_entry_prefetch(self,box.grow(1),{}),"new Deferred operation starts independently")
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		queue.pump_entry_prefetch()
		if queue._jobs.has(b):
			var job:Dictionary=queue._jobs[b]
			if not job.has("worker") and job.has("result") and not job.get("native_binding_pending",true):break
		await process_frame
	check(second_pool.snapshot().get("streamed_loads",0)==0 and second_pool.snapshot().produced==0,"resident cross-operation ticket causes zero new native producers")
	var result:Dictionary=queue._jobs.get(b,{}).get("result",{})
	check(is_instance_valid(result.get("scene")) and result.scene.get_child(0).mesh.surface_get_material(0).albedo_texture.get_instance_id()==first.id,"Deferred binds the exact first texture object")
	if is_instance_valid(result.get("scene")):
		check(Assets.cache_scene(b,result.scene,fixture.candidate.source_sha),"second model cache owns the reused texture");result.erase("scene")
		Paint._texture_refs.clear()
		if queue.has_method("_publish_native_texture_owners"):queue.call("_publish_native_texture_owners",b,queue._jobs[b])
		check(Paint.retained_texture(key)!=null,"Deferred main publication restores weak identity without rescanning cached scenes")
		Paint._texture_refs.clear();queue._jobs[b].token.cancel()
		if queue.has_method("_publish_native_texture_owners"):queue.call("_publish_native_texture_owners",b,queue._jobs[b])
		check(Paint.retained_texture(key)==null,"cancelled Deferred job cannot publish a weak identity")
	await queue.quiesce();queue.copies.clear();queue.shutdown();queue.free();fixture.free();result={}
	Assets.evict_cached_scene(a);Assets.evict_cached_scene(b)
	deadline=Time.get_ticks_msec()+3000
	while first.weak.get_ref()!=null and Time.get_ticks_msec()<deadline:await process_frame
	check(first.weak.get_ref()==null,"weak catalogue retains no texture after both real owners retire")
	print("NATIVE_TEXTURE_CROSS_OPERATION ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
