extends SceneTree
## Isolated real-4.8 residency contract; synthetic external products only.
const Products=preload("res://scripts/world3d/model_texture_products.gd")
const Binding=preload("res://scripts/world3d/model_texture_bindings.gd")
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
var checks:=0
var failures:Array[String]=[]
var report:Dictionary={}
var folder:String
var errors:Errors
class Errors extends Logger:
	var mutex:=Mutex.new()
	var messages:Array[String]=[]
	func _log_error(function:String,_file:String,_line:int,code:String,rationale:String,_notify:bool,_type:int,_backtraces:Array)->void:
		mutex.lock();messages.append(function+": "+code+" "+rationale);mutex.unlock()
class InvalidPool extends Pool:
	var empty_native:=false
	func _load_stream(_plan:Dictionary,_digest:String)->Texture2D:
		if empty_native:return ClassDB.instantiate("StreamedTexture2D")
		return ImageTexture.create_from_image(Image.create(4,4,false,Image.FORMAT_RGBA8))
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func fixture()->Node3D:
	var scene:=Node3D.new();scene.name="BudgetFixture"
	for index:int in 2:
		var image:=Image.create(256>>index,256>>index,false,Image.FORMAT_RGBA8);image.fill(Color(.8,.3+index*.2,.15));image.generate_mipmaps()
		var material:=StandardMaterial3D.new();material.albedo_texture=ImageTexture.create_from_image(image)
		var node:=MeshInstance3D.new();node.name="Panel%d"%index;node.mesh=QuadMesh.new();node.mesh.material=material;node.position.x=index-.5
		scene.add_child(node);node.owner=scene
	return scene
func admit(pool:RefCounted,consumer:String,plan:Dictionary)->Dictionary:
	var offer:Dictionary=pool.offer(plan)
	check(pool.admission.reserve_bundle(consumer,{"estimated_bytes":offer.scratch_bytes,"exclusive":false},offer.retained),"admit "+consumer)
	pool.commit(consumer,offer);pool.admission.park(consumer);return offer
func load_outputs(pool:RefCounted,consumer:String,rows:Dictionary)->void:
	for key:String in rows:
		var worker:=Thread.new();check(worker.start(pool.load_stream.bind(consumer,key,str(rows[key].path).sha256_text(),rows[key]))==OK,"start native output off main")
		while worker.is_alive():await process_frame
		check(bool(worker.wait_to_finish()),"complete native output "+consumer)
	pool.admission.release(consumer)
func bytes_used()->int:return int(Engine.get_singleton("TextureStreaming").call("get_memory_budget_bytes_used"))
func settle()->void:
	for index:int in 12:await process_frame;await RenderingServer.frame_post_draw
func finish()->void:
	OS.remove_logger(errors);report.diagnostics=errors.messages.duplicate();check(report.diagnostics.is_empty(),"zero engine or script diagnostics")
	report.checks=checks;report.failures=failures
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STREAMED_HANDOFF_GPU ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
func mixed_native(planned:Dictionary)->void:
	var pool:=Pool.new();pool.admission=Admission.new();var key:String=planned.rows.keys()[0]
	var plan:Dictionary={"rows":{key:planned.rows[key],"ordinary":{"path":"ordinary","width":4,"height":4,"source_bytes":64,"output_bytes":64,"extension":"png","cache_limit":64}}}
	admit(pool,"mixed",plan);await load_outputs(pool,"mixed",{key:planned.rows[key]})
	var pixels:=Image.create(4,4,false,Image.FORMAT_RGBA8)
	check(pool.publish("mixed","ordinary","fixture",pixels),"mixed real native consumer also produces an ordinary Image")
	var owners:Dictionary=pool.textures("mixed");var material:=StandardMaterial3D.new();material.albedo_texture=owners[key]
	var before:int=pool.admission.reserved_bytes
	check(not pool.handoff_streamed("mixed",owners) and pool.admission.reserved_bytes==before,"default mixed GPU handoff retains all charges")
	check(pool.handoff_streamed("mixed",owners,[key]) and pool.admission.reserved_bytes==128 and pool.snapshot().handoff_outputs==1,"bound native GPU subset transfers while ordinary Image stays fully charged")
	check(pool.handoff_streamed("mixed",owners,[key,key]) and pool.admission.reserved_bytes==128,"repeated real native subset does not release ordinary pixels")
	owners.clear();pixels=null;pool.release("mixed")
	await settle();check(pool.admission.reserved_bytes==0 and bytes_used()>0,"mixed pool final release preserves the actual native material lifetime")
	material=null;await settle();check(bytes_used()==0,"mixed material final release retires actual engine residency")
func run()->void:
	if DisplayServer.get_name()=="headless" or not Prep.Streamed.enabled():quit(2);return
	errors=Errors.new();OS.add_logger(errors)
	folder=Prep.Paths.external_root();DirAccess.make_dir_recursive_absolute(folder)
	create_timer(50).timeout.connect(func():quit(2))
	Prep.Pixels.Policy.verify_packages=false
	check(bytes_used()==0,"isolated engine residency starts empty")
	var source:=fixture();var product:=Products.prepare(source,folder)
	check(product.ok and product.stats.textures==2,"offline fixture splits two native products")
	var packed:=PackedScene.new();check(packed.pack(source)==OK,"pack real texture-free materials")
	var table:=Products.read_table(product.texture_table,folder);var planned:=Binding.texture_plan(table.table,folder)
	check(planned.ok and planned.plan.rows.size()==2,"immutable native plan deduplicates two products")
	var pool:=Pool.new();pool.admission=Admission.new()
	var offer:=admit(pool,"leader",planned.plan);admit(pool,"follower",planned.plan);pool.admission.release("follower")
	await load_outputs(pool,"leader",planned.plan.rows)
	var owners:Dictionary=pool.textures("leader");var binding:=Binding.begin(packed,planned["keys"],product.table_sha)
	check(binding.ok and Binding.adopt(binding,owners),"actual material binding adopts completed owners")
	while Binding.step(binding)==Binding.PROGRESS:pass
	check(binding.sets==2,"real materials bind both native owners")
	var scene:Node3D=packed.instantiate();root.add_child(scene)
	var camera:=Camera3D.new();camera.position=Vector3(0,0,3);scene.add_child(camera);camera.current=true
	await settle();report.resident_before_handoff=bytes_used()
	check(report.resident_before_handoff>0,"engine independently accounts native residency before transfer")
	check(pool.admission.reserved_bytes==int(planned.plan.output_bytes)*2,"temporary ledger holds the unique full-chain conservative envelope")
	var charged:int=pool.admission.reserved_bytes;var wrong:Dictionary=owners.duplicate();wrong.erase(wrong.keys()[-1])
	check(not pool.handoff_streamed("leader",wrong) and pool.admission.reserved_bytes==charged,"missing native owner has no partial effect")
	ProjectSettings.set_setting("rendering/textures/streaming/memory_budget_enabled",false)
	check(not pool.handoff_streamed("leader",owners) and pool.admission.reserved_bytes==charged,"disabled memory budget prevents transfer")
	ProjectSettings.set_setting("rendering/textures/streaming/memory_budget_enabled",true)
	pool.cancel("leader")
	check(not pool.handoff_streamed("leader",owners) and pool.admission.reserved_bytes==charged,"cancelled consumer cannot transfer")
	check(pool.handoff_streamed("follower",owners),"active follower transfers the shared completed native outputs")
	check(pool.admission.reserved_bytes==0 and pool.snapshot().retained_bytes==0,"production envelope is fully released without dropping resources")
	check(pool.handoff_streamed("follower",owners) and pool.snapshot().handoff_outputs==2,"repeat native transfer cannot release twice")
	check(pool.admission.can_admit("next",{"estimated_bytes":pool.admission.byte_limit+1,"exclusive":true}),"completed native outputs cannot block the next exclusive producer")
	var late:=admit(pool,"late",planned.plan);pool.admission.release("late")
	check(late.retained.is_empty() and late.leaders.is_empty() and pool.textures("late")==owners and pool.snapshot().streamed_loads==2,"post-transfer consumers reuse exact owners without new native I/O")
	report.conservative_full_chain_handoff_bytes=pool.snapshot().handoff_full_chain_bytes;report.pool=pool.snapshot();report.resident_after_handoff=bytes_used()
	check(report.resident_after_handoff>0,"engine residency remains accounted after temporary-ledger transfer")
	var weak:WeakRef=weakref(owners.values()[0]);wrong.clear();owners.clear();binding.clear()
	for consumer:String in ["leader","follower","late"]:pool.release(consumer)
	check(pool._entries.is_empty() and pool.admission.reserved_bytes==0 and weak.get_ref()!=null,"last pool lease ends while actual material retains its native owner")
	await settle();check(bytes_used()>0,"material lifetime continues engine residency after pool release")
	scene.free();source.free();packed=null;product.clear();offer.clear();late.clear()
	await settle()
	var deadline:=Time.get_ticks_msec()+8000
	while bytes_used()!=0 and Time.get_ticks_msec()<deadline:await process_frame
	report.resident_after_final_owner=bytes_used()
	check(weak.get_ref()==null and bytes_used()==0,"last actual owner destruction retires native streaming state to zero")
	for empty:bool in [false,true]:
		var invalid:=InvalidPool.new();invalid.empty_native=empty;invalid.admission=Admission.new()
		var one:Dictionary=planned.plan.duplicate();var key:String=one.rows.keys()[0];one.rows={key:one.rows[key]}
		admit(invalid,"invalid",one);await load_outputs(invalid,"invalid",one.rows)
		var invalid_owners:Dictionary=invalid.textures("invalid");var before:int=invalid.admission.reserved_bytes
		check(not invalid.handoff_streamed("invalid",invalid_owners) and invalid.admission.reserved_bytes==before,"unloaded STEX cannot transfer" if empty else "real ImageTexture cannot masquerade as managed STEX")
		invalid_owners.clear();invalid.release("invalid")
		check(invalid.admission.reserved_bytes==0,"invalid result still retires its original lease normally")
	var unregistered:=Pool.new();unregistered.admission=Admission.new()
	var one:Dictionary=planned.plan.duplicate();var key:String=one.rows.keys()[0];one.rows={key:one.rows[key]}
	admit(unregistered,"unregistered",one)
	ProjectSettings.set_setting("rendering/textures/streaming/enabled",false)
	await load_outputs(unregistered,"unregistered",one.rows)
	ProjectSettings.set_setting("rendering/textures/streaming/enabled",true)
	var unregistered_owners:Dictionary=unregistered.textures("unregistered");var before:int=unregistered.admission.reserved_bytes
	check(not unregistered.handoff_streamed("unregistered",unregistered_owners) and unregistered.admission.reserved_bytes==before,"enabled-after-creation STEX stays charged because its native streaming state was never registered")
	unregistered_owners.clear();unregistered.release("unregistered")
	await settle();check(bytes_used()==0,"negative cases leave no native residency")
	await mixed_native(planned.plan)
	finish()
