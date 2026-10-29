extends SceneTree
## External native-model candidate only. Pixel readbacks below are verification,
## after runtime counters; preparation/publication must never read pixels back.
const Products=preload("res://scripts/world3d/model_texture_products.gd")
const Binding=preload("res://scripts/world3d/model_texture_bindings.gd")
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
var failures:Array[String]=[]
var checks:=0
var folder:String
var report:Dictionary={}
class Cancel extends RefCounted:
	func is_cancelled()->bool:return true
class HeldPool extends Pool:
	var gate:=Semaphore.new()
	var mutex:=Mutex.new()
	var held:=false
	var first:=true
	func _load_stream(plan:Dictionary,digest:String)->Texture2D:
		var texture:=super(plan,digest)
		mutex.lock();var hold:=first;first=false;held=hold;mutex.unlock()
		if hold:gate.wait()
		return texture
	func is_held()->bool:
		mutex.lock();var value:=held;mutex.unlock();return value
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func fixture()->Node3D:
	var scene:=Node3D.new();scene.name="NativeTextureFixture"
	var rgb:=Image.create(3,5,false,Image.FORMAT_RGB8)
	for y:int in 5:
		for x:int in 3:rgb.set_pixel(x,y,Color(.2+float(x)*.3,.1+float(y)*.17,.65))
	var rgba:=Image.create(4,4,false,Image.FORMAT_RGBA8)
	for y:int in 4:
		for x:int in 4:rgba.set_pixel(x,y,Color(.8,.15+float(x)*.2,.15+float(y)*.2,.25 if x==y else 1.))
	rgba.generate_mipmaps()
	var textures:Array[Texture2D]=[ImageTexture.create_from_image(rgb),ImageTexture.create_from_image(rgba)]
	for index:int in 3:
		var node:=MeshInstance3D.new();node.name="Panel%d"%index;scene.add_child(node);node.owner=scene;node.position.x=float(index-1)*1.05
		var mesh:=QuadMesh.new();mesh.size=Vector2(.95,.95);node.mesh=mesh
		var material:=StandardMaterial3D.new();material.resource_name="Material%d"%index
		material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS;material.cull_mode=BaseMaterial3D.CULL_DISABLED
		material.albedo_texture=textures[index%2];material.roughness=.7;material.normal_enabled=true;material.normal_scale=.2
		# One actual product is used simultaneously as color, normal and masks.
		material.normal_texture=textures[index%2];material.detail_normal=textures[index%2];material.bent_normal_texture=textures[index%2]
		material.roughness_texture=textures[index%2];material.ao_texture=textures[index%2]
		if index==1:material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;material.alpha_scissor_threshold=.5
		if index==0:mesh.material=material
		elif index==1:node.material_override=material
		else:node.set_surface_override_material(0,material)
	return scene
func admit(pool:RefCounted,name_:String,plan:Dictionary)->Dictionary:
	var offer:Dictionary=pool.offer(plan)
	check(pool.admission.reserve_bundle(name_,{"estimated_bytes":offer.scratch_bytes,"exclusive":false},offer.retained),"common ledger admits "+name_)
	pool.commit(name_,offer)
	return {"pool":pool,"consumer":name_,"leaders":offer.leaders,"cached":offer.cached,"active":true}
func prepare(planned:Dictionary,shared:Dictionary={})->Dictionary:
	if not shared.is_empty() and not shared.active:check(shared.pool.admission.resume_worker(shared.consumer),"continuation reacquires its existing worker slot")
	var worker:=Thread.new();check(worker.start(Prep.prepare.bind(planned.sources,planned.plan,folder,null,true,shared,true if not shared.is_empty() else false))==OK,"preparation starts off main thread")
	while worker.is_alive():await process_frame
	var packet:Dictionary=worker.wait_to_finish()
	if not shared.is_empty():shared.pool.admission.park(shared.consumer);shared.active=false
	return packet
func viewport(scene:Node3D)->SubViewport:
	var view:=SubViewport.new();view.size=Vector2i(384,192);view.own_world_3d=true;view.use_taa=false;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view);view.add_child(scene)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.08,.08,.08);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.6;scene.add_child(environment)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.8;camera.position=Vector3(0,0,4);scene.add_child(camera);camera.current=true
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-20,-20,0);scene.add_child(light)
	return view
func independent_source(scene:Node3D)->bool:
	for node:MeshInstance3D in scene.get_children():
		var material:Material=node.material_override
		if material==null:material=node.get_surface_override_material(0)
		if material==null:material=node.mesh.surface_get_material(0)
		if material==null or not material.albedo_texture is ImageTexture or material.has_meta(Products.BINDINGS_META):return false
	return true
func finish()->void:
	report.checks=checks;report.failures=failures
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("MODEL_TEXTURE_PREPARATION ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
func run()->void:
	if DisplayServer.get_name()=="headless" or not Prep.Streamed.enabled():quit(2);return
	folder=Prep.Paths.external_root().path_join("native_gpu_%d"%OS.get_process_id());DirAccess.make_dir_recursive_absolute(folder)
	create_timer(100).timeout.connect(func():quit(2))
	Prep.Pixels.Policy.verify_packages=false;Prep.Pixels.profile_enabled=true
	var original:=fixture();var prepared:=Products.prepare(original,folder)
	check(prepared.ok and prepared.stats.textures==2,"offline fixture publishes two native products for eighteen slots")
	var packed:=PackedScene.new();check(packed.pack(original)==OK,"pack texture-free graph")
	var native_path:=folder.path_join("split.scn");check(ResourceSaver.save(packed,native_path,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"save texture-free native scene")
	Products.restore(prepared);packed=null
	var table:=Products.read_table(prepared.texture_table,folder)
	check(table.ok,"read the published native table once")
	var planned:=Binding.texture_plan(table.table,folder)
	check(planned.ok and planned.plan.rows.size()==2,"native plan deduplicates material roles without PNG sidecars")
	var standalone_ledger:=Admission.new();check(standalone_ledger.reserve("standalone",{"estimated_bytes":planned.plan.estimated_bytes,"exclusive":false}),"standalone receives its ordinary preparation reservation")
	var standalone:=await prepare(planned)
	check(standalone.error.is_empty() and standalone.get("uploaded_textures",{}).size()==2,"standalone preserves its admitted direct STEX plan")
	report.standalone=standalone.get("profile",{});report.standalone_error=standalone.error
	standalone.clear();standalone_ledger.release("standalone")
	if not failures.is_empty():original.free();prepared.clear();finish();return
	check(not Prep.prepare(planned.sources,planned.plan,folder,null,true,{},false,true).error.is_empty(),"mutable source cannot masquerade as native immutable plan")
	Prep.Pixels.Policy.verify_packages=true
	check(not Prep.prepare(planned.sources,planned.plan,folder).error.is_empty(),"strict diagnostic cannot silently bypass its source snapshot contract")
	Prep.Pixels.Policy.verify_packages=false
	check(Prep.prepare(planned.sources,planned.plan,folder,Cancel.new()).cancelled,"cancelled native plan performs no work")
	var invalid:Dictionary=planned.plan.duplicate(true);invalid.rows.values()[0].path=folder.path_join("fake.png")
	check(not Prep.prepare(planned.sources,invalid,folder).error.is_empty(),"model product marker cannot authorize an arbitrary source")
	invalid=planned.plan.duplicate(true);invalid.output_bytes=1
	check(not Prep.prepare(planned.sources,invalid,folder).error.is_empty(),"model product plan cannot understate admitted output")
	var pool:=Pool.new();pool.admission=Admission.new()
	var leader:=admit(pool,"leader",planned.plan);var follower:=admit(pool,"follower",planned.plan)
	Prep.Pixels.reset_profile()
	var waiting:=await prepare(planned,follower)
	check(waiting.error.is_empty() and waiting.waiting_pixels and waiting.images.is_empty(),"follower returns pending rather than blocking a worker")
	var packet:=await prepare(planned,leader);var followed:=await prepare(planned,follower)
	check(packet.error.is_empty() and followed.error.is_empty() and pool.ready("follower"),"native producer and continuation complete normally")
	check(packet.images.is_empty() and followed.images.is_empty() and pool.snapshot().produced==2 and pool.snapshot().streamed_loads==2,"two consumers produce two unique native textures and no CPU images")
	for key:String in planned.plan.rows:check(packet.uploaded_textures[key]==followed.uploaded_textures[key] and packet.uploaded_textures[key].is_class("StreamedTexture2D"),"normal/color consumers share the exact native Texture2D owner")
	packed=ResourceLoader.load(native_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
	var binding:=Binding.begin(packed,planned["keys"],prepared.table_sha)
	check(binding.ok and Binding.adopt(binding,packet.uploaded_textures),"binding adopts the complete prepared native dependency set")
	while Binding.step(binding)==Binding.PROGRESS:pass
	check(binding.sets==18,"all actual material slots bind the prepared products")
	for entry:Dictionary in binding.bindings:
		for index:int in entry.slots.size():check(entry.material.get(entry.slots[index])==packet.uploaded_textures[entry.targets[index]],"material slot retains the exact shared native RID")
	var again:=Binding.begin(packed,planned["keys"],prepared.table_sha);Binding.adopt(again,packet.uploaded_textures)
	while Binding.step(again)==Binding.PROGRESS:pass
	check(again.sets==0 and again.unchanged==18,"repeat binding performs no redundant material setters")
	report.preparation=packet.profile;report.pool=pool.snapshot();report.counters=Prep.Pixels.profile_snapshot("").counters
	check(packet.profile.decoded==0 and packet.profile.source_sha_reads==0 and packet.profile.final_sha_reads==0 and pool.snapshot().uploads==0,"native handoff has no source decode/hash or ImageTexture upload")
	for key:String in planned.plan.rows:
		var row:Dictionary=planned.plan.rows[key];var pixels:Image=packet.uploaded_textures[key].get_image()
		check(pixels.get_format()==int(row.format) and pixels.get_data_size()==int(row.output_bytes) and pixels.get_mipmap_count()+1==row.mip_sizes.size(),"verification preserves original RGB8/base-only or RGBA8/mip layout")
	check(independent_source(original),"source graph still uses independent original ImageTextures after native binding")
	var before:=viewport(original);var after:=viewport(packed.instantiate())
	var difference:=-1;var visible_pixels:=0
	for frame:int in 180:
		await process_frame;await RenderingServer.frame_post_draw
		if frame<12 or frame%6!=0:continue
		var a:=before.get_texture().get_image();var b:=after.get_texture().get_image()
		var left:=a.get_data();var right:=b.get_data();difference=0
		for byte:int in left.size():difference+=int(left[byte]!=right[byte])
		# The center texel deliberately lies in an alpha-scissor hole. Count the
		# actual non-background panel pixels instead of probing that empty point.
		visible_pixels=0
		for byte:int in range(0,left.size(),4):
			if left[byte]!=left[0] or left[byte+1]!=left[1] or left[byte+2]!=left[2]:visible_pixels+=1
		if difference==0 and visible_pixels>1000:break
	check(visible_pixels>1000 and difference==0,"source and split scenes render identical real GPU pixels")
	report.render_mismatched_bytes=difference;report.render_visible_pixels=visible_pixels
	var source_capture:=before.get_texture().get_image();var split_capture:=after.get_texture().get_image()
	check(source_capture.save_png(folder.path_join("source.png"))==OK and split_capture.save_png(folder.path_join("split.png"))==OK,"preserve lossless framebuffer evidence locally")
	check(source_capture.save_webp(folder.path_join("source.webp"),true,.9)==OK and split_capture.save_webp(folder.path_join("split.webp"),true,.9)==OK,"export original-size lossy quality-90 WebP review copies")
	report.screenshot_encoding={"lossy":true,"quality":.9,"dimensions":[384,192]}
	before.free();after.free();packed=null;Binding.release(binding);Binding.release(again)
	var weak:WeakRef=weakref(packet.uploaded_textures.values()[0])
	packet.clear();followed.clear();waiting.clear();prepared.clear()
	pool.release("leader");pool.admission.release("leader")
	check(weak.get_ref()!=null,"remaining consumer owns the native texture after sibling retirement")
	pool.release("follower");pool.admission.release("follower")
	check(weak.get_ref()==null and pool.admission.reserved_bytes==0,"last consumer releases native owners and every shared reservation")
	await cancellation(planned)
	var streaming:=Engine.get_singleton("TextureStreaming");var deadline:=Time.get_ticks_msec()+8000
	while int(streaming.call("get_memory_budget_bytes_used"))!=0 and Time.get_ticks_msec()<deadline:await process_frame
	check(int(streaming.call("get_memory_budget_bytes_used"))==0,"engine streaming ledger drains after all owners retire")
	finish()
func cancellation(planned:Dictionary)->void:
	var key:String=planned.plan.rows.keys()[0];var row:Dictionary=planned.plan.rows[key]
	var one:Dictionary={"rows":{key:row},"output_bytes":row.output_bytes,"estimated_bytes":int(row.output_bytes)*2+Prep.workspace_bytes(row)}
	var pool:=HeldPool.new();pool.admission=Admission.new()
	admit(pool,"old",one);admit(pool,"waiting",one);pool.admission.park("waiting")
	var digest:String=row.path.sha256_text();var worker:=Thread.new();worker.start(pool.load_stream.bind("old",key,digest,row))
	var deadline:=Time.get_ticks_msec()+5000
	while not pool.is_held() and Time.get_ticks_msec()<deadline:await process_frame
	check(pool.is_held() and not pool.ready("waiting"),"native in-flight owner remains unavailable to followers")
	check(not pool.load_stream("old",key,digest,row),"duplicate native claim launches no second load")
	pool.cancel("old");var charge:int=pool.admission.reserved_bytes
	admit(pool,"replacement",one)
	var replacement:=Thread.new();replacement.start(pool.load_stream.bind("replacement",key,digest,row))
	while replacement.is_alive():await process_frame
	check(replacement.wait_to_finish() and pool.ready("waiting"),"replacement completes while cancelled producer is held")
	var texture:Texture2D=pool.textures("replacement")[key]
	check(pool.admission.reserved_bytes>=charge,"in-flight old workspace stays charged during takeover")
	pool.gate.post()
	while worker.is_alive():await process_frame
	check(not worker.wait_to_finish() and pool.textures("waiting")[key]==texture,"late cancelled result cannot overwrite replacement")
	check(pool.snapshot().streamed_loads==2 and pool.snapshot().produced==1 and pool.snapshot().discarded_uploads==1,"only cancelled attempt and replacement perform native loads")
	texture=null
	for consumer:String in ["old","waiting","replacement"]:pool.release(consumer);pool.admission.release(consumer)
	check(pool.admission.reserved_bytes==0,"cancel and takeover retire every reservation")
