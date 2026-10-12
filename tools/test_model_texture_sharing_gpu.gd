extends "res://tools/test_asset_import_preparation.gd"
## Small real-resource regression. Run only on the coordinated private desktop;
## native reads allocate ImageTextures. No HTTP, maps or authored assets change.
const Textures=preload("res://scripts/world3d/model_texture_cache.gd")
var test_folder:String

func material_of(scene:Node)->StandardMaterial3D:
	var node:=Io.find_named(scene,"One") as MeshInstance3D
	return node.get_active_material(0) as StandardMaterial3D if node!=null else null

func texture_of(scene:Node)->Texture2D:
	var material:=material_of(scene)
	return material.albedo_texture if material!=null else null

func material_snapshot(scene:Node)->Dictionary:
	var material:=material_of(scene)
	return {"color":material.albedo_color,"roughness":material.roughness,"metallic":material.metallic,"filter":material.texture_filter,"repeat":material.texture_repeat,"uv":material.uv1_scale,"cull":material.cull_mode,"transparency":material.transparency}

func textured_glb(path:String,alternate:bool)->void:
	var content:=fixture()
	var pixels:=Image.create(8,8,false,Image.FORMAT_RGBA8)
	pixels.fill(Color(0.17,0.39,0.61,1))
	pixels.set_pixel(2,3,Color(0.8,0.2,0.1,1))
	var png:=pixels.save_png_to_buffer()
	var binary:PackedByteArray=content.binary
	var data:Dictionary=content.data
	data.bufferViews.append({"buffer":0,"byteOffset":binary.size(),"byteLength":png.size()})
	binary.append_array(png);data.buffers[0].byteLength=binary.size()
	data.images=[{"bufferView":1,"mimeType":"image/png"}]
	data.textures=[{"source":0,"sampler":0}]
	data.samplers=[{"magFilter":9729 if alternate else 9728,"minFilter":9729 if alternate else 9728,"wrapS":33071 if alternate else 10497,"wrapT":33071 if alternate else 10497}]
	data.materials[0].pbrMetallicRoughness.baseColorTexture={"index":0}
	if alternate:
		data.materials[0].pbrMetallicRoughness.roughnessFactor=0.27
		data.materials[0].pbrMetallicRoughness.baseColorFactor=[0.7,0.8,0.9,1]
		data.materials[0].doubleSided=true
	write_glb(path,data,binary)

func release_read(packet:Dictionary)->void:
	Drainer.dispose_result(packet)
	Drainer.synchronize_transfer()

func read_pair(a:String,b:String)->Array[Dictionary]:
	var first:=Compiled.read(a);var second:=Compiled.read(b)
	check(first.hit and second.hit,"two temporary compiled products pass native source/product validation")
	return [first,second]

func test_compiled_pair(a:String,b:String)->void:
	Textures.enabled=false
	var pair:=read_pair(a,b)
	if not pair[0].hit or not pair[1].hit:
		for packet:Dictionary in pair:release_read(packet)
		return
	check(pair[0].packed!=pair[1].packed,"native reads return independent PackedScene allocations")
	var first:=Compiled.instantiate(pair[0].packed);var second:=Compiled.instantiate(pair[1].packed)
	if first==null or second==null:
		check(false,"both compiled products instantiate")
		if first!=null:Drainer.dispose_scene(first)
		if second!=null:Drainer.dispose_scene(second)
		for packet:Dictionary in pair:release_read(packet)
		return
	var first_appearance:=material_snapshot(first);var second_appearance:=material_snapshot(second)
	check(texture_of(first) is ImageTexture and texture_of(second) is ImageTexture,"real native textures are ImageTextures")
	check(texture_of(first)!=texture_of(second),"candidate off retains independent identical-pixel allocations")
	var key:String=texture_of(first).get_meta(Textures.PIXEL_KEY,"")
	check(Textures._valid_key(key) and key==texture_of(second).get_meta(Textures.PIXEL_KEY,""),"offline pixel/layout stamp survives SCN save and fresh native reads")
	check(first_appearance.filter!=second_appearance.filter and first_appearance.repeat!=second_appearance.repeat and first_appearance.roughness!=second_appearance.roughness,"fixture has genuinely different sampler and material settings")
	var a_texture:WeakRef=weakref(texture_of(first));var b_texture:WeakRef=weakref(texture_of(second))
	var a_material:WeakRef=weakref(material_of(first));var b_material:WeakRef=weakref(material_of(second))
	Drainer.dispose_scene(first);Drainer.dispose_scene(second);first=null;second=null
	check(a_texture.get_ref()!=null and b_texture.get_ref()!=null,"original native templates still own textures after their instances are freed")
	for packet:Dictionary in pair:release_read(packet)
	pair.clear()
	check(a_texture.get_ref()==null and b_texture.get_ref()==null,"off-mode templates release actual texture objects when last owners disappear")
	check(a_material.get_ref()==null and b_material.get_ref()==null,"off-mode material objects are not retained by the helper")

	Textures.enabled=true
	pair=read_pair(a,b)
	if not pair[0].hit or not pair[1].hit:
		for packet:Dictionary in pair:release_read(packet)
		return
	check(Library.cache_packed(a,pair[0].packed,pair[0].source_digest) and Library.cache_packed(b,pair[1].packed,pair[1].source_digest),"production library accepts verified native templates")
	first=Library.instantiate(a);second=Library.instantiate(b)
	check(first!=null and second!=null,"production library instantiates both cached models")
	if first==null or second==null:
		if first!=null:Drainer.dispose_scene(first)
		if second!=null:Drainer.dispose_scene(second)
		Library.evict_cached_scene(a);Library.evict_cached_scene(b)
		for packet:Dictionary in pair:release_read(packet)
		return
	check(material_of(first)!=material_of(second),"interning preserves distinct material objects")
	check(texture_of(first)==texture_of(second),"candidate on shares identical texture pixels across independent native products")
	check(material_snapshot(first)==first_appearance and material_snapshot(second)==second_appearance,"sharing preserves each material's tint roughness sampler UV cull and transparency")
	a_texture=weakref(texture_of(first))
	check(Textures._textures.has(key) and Textures._textures[key].get_ref()==texture_of(first),"weak pool points to the actual shared native texture")
	Drainer.dispose_scene(first);Drainer.dispose_scene(second);first=null;second=null
	check(a_texture.get_ref()!=null,"removing instances alone does not falsely claim cached textures are released")
	Library.evict_cached_scene(a);Library.evict_cached_scene(b)
	for packet:Dictionary in pair:release_read(packet)
	pair.clear();Drainer.synchronize_transfer()
	check(a_texture.get_ref()==null and Textures._textures[key].get_ref()==null,"clearing cache and native owners frees texture despite its weak pool entry")

static func worker_scene(path:String,content_root:String)->Dictionary:
	var packet:=Compiled.read(path,"",content_root)
	if not packet.hit:return {"native_packet":packet,"scene":null,"thread_id":OS.get_thread_caller_id()}
	var scene:=Compiled.instantiate(packet.packed)
	return {"native_packet":packet,"scene":scene,"thread_id":OS.get_thread_caller_id()}

func test_worker_handoff(a:String,b:String)->void:
	Textures.enabled=true
	var first:=Library.instantiate(a)
	check(first!=null,"main publishes a canonical native texture before worker handoff")
	if first==null:return
	var canonical:WeakRef=weakref(texture_of(first));var keys_before:=Textures._textures.size()
	var worker:=Thread.new();var err:=worker.start(worker_scene.bind(b,Paths.external_root()))
	check(err==OK,"private native-reader worker starts")
	if err!=OK:
		Drainer.dispose_scene(first);Library.evict_cached_scene(a);return
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish();Drainer.synchronize_transfer()
	check(result.thread_id!=OS.get_main_thread_id() and result.scene!=null,"worker really read and instantiated the second native model")
	if result.scene==null:
		release_read(result);Drainer.dispose_scene(first);Library.evict_cached_scene(a);return
	check(texture_of(result.scene)!=canonical.get_ref() and Textures._textures.size()==keys_before,"worker instantiation never interns or mutates the main texture pool")
	var appearance:=material_snapshot(result.scene)
	# Leaf-style overrides leave a second material on the ArrayMesh itself.
	# Both reachable material slots must rebind, not just the currently active
	# override. A separate non-render owner on the original PackedScene keeps
	# the old texture alive until that real owner is released; no probe metadata
	# is added to the Texture (which would correctly disable interning).
	result.native_packet.packed.set_meta("test_retained_texture",texture_of(result.scene))
	var mesh:=Io.find_named(result.scene,"One") as MeshInstance3D
	var other_mesh:=Io.find_named(result.scene,"Two") as MeshInstance3D
	var private_material:StandardMaterial3D=material_of(result.scene).duplicate()
	mesh.set_surface_override_material(0,private_material)
	other_mesh.set_surface_override_material(0,private_material)
	private_material=null;mesh=null;other_mesh=null
	var original:WeakRef=weakref(texture_of(result.scene))
	var owner:WeakRef=weakref(result.native_packet.packed)
	check(Library.cache_scene(b,result.scene,result.native_packet.source_digest),"main production cache_scene accepts deferred native scene and performs sharing")
	result.scene=null
	var second:=Library.instantiate(b)
	check(second!=null and texture_of(second)==canonical.get_ref(),"main handoff shares the deferred model's texture")
	if second!=null:
		check(material_snapshot(second)==appearance,"deferred repack retains the independent material settings")
		var cached_mesh:=Io.find_named(second,"One") as MeshInstance3D
		var stored_material:=cached_mesh.mesh.surface_get_material(0) as StandardMaterial3D
		check(stored_material!=material_of(second) and stored_material.albedo_texture==canonical.get_ref(),"hidden original mesh material also shares pixels after leaf-style override handoff")
		stored_material=null;cached_mesh=null
	check(owner.get_ref()!=null and original.get_ref()!=null,"original PackedScene's non-render owner still retains the replaced texture")
	release_read(result)
	check(owner.get_ref()==null and original.get_ref()==null,"old native owner and replaced texture retire only after their actual packet is released")
	Library.evict_cached_scene(a);Library.evict_cached_scene(b)
	check(canonical.get_ref()!=null,"live instances retain shared texture after library eviction")
	Drainer.dispose_scene(first)
	if second!=null:Drainer.dispose_scene(second)
	first=null;second=null;Drainer.synchronize_transfer()
	check(canonical.get_ref()==null,"after final instance destruction the weak pool does not retain the shared texture")

func native_variant(label:String,format_:Image.Format,mips:bool=false,changed:bool=false,unknown_metadata:bool=false,local:bool=false)->String:
	# Direct authored SCN fixture is needed for mip/float/local-resource cases:
	# ordinary GLTF import does not preserve every one of those image layouts.
	var image:=Image.create(8,8,false,format_);image.fill(Color.BLACK)
	if changed:image.set_pixel(1,1,Color.RED)
	if mips:image.generate_mipmaps()
	var texture:=ImageTexture.create_from_image(image)
	var material:=StandardMaterial3D.new();material.albedo_texture=texture
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3(0,1,0.5)])
	var geometry:=ArrayMesh.new();geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);geometry.surface_set_material(0,material)
	var scene:=Node3D.new();var visual:=MeshInstance3D.new();visual.name="One";visual.mesh=geometry;scene.add_child(visual)
	Textures.stamp(scene)
	check(Textures._valid_key(texture.get_meta(Textures.PIXEL_KEY,"")),label+": actual GPU image receives an offline identity")
	if unknown_metadata:texture.set_meta("author_identity","preserve")
	if local:texture.resource_local_to_scene=true
	Compiled._own(scene,scene)
	var packed:=PackedScene.new();var err:=packed.pack(scene)
	check(err==OK and Compiled._valid_packed(packed),label+": exact closed native schema remains valid")
	var path:=test_folder.path_join(label+".scn")
	if err==OK:err=ResourceSaver.save(packed,path,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)
	check(err==OK and ResourceLoader.get_dependencies(path).is_empty(),label+": real native fixture saves without external dependencies")
	Drainer.dispose_scene(scene);packed=null;material=null;texture=null;geometry=null;image=null
	Drainer.synchronize_transfer()
	return path

func open_variant(path:String)->Dictionary:
	var loaded:Resource=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var packed:=loaded as PackedScene
	var valid:=packed!=null and Compiled._valid_packed(packed)
	check(valid,path.get_file()+": independently reloaded native graph validates")
	if not valid:
		loaded=null;packed=null;Drainer.synchronize_transfer();return {}
	# This fixture owns and validates its SCN, without inventing a formal GLB
	# manifest. The GLB/Compiled.read identity chain is covered above.
	packed.set_meta("compiled_asset_validated",true)
	return {"packed":packed,"scene":Compiled.instantiate(packed)}

func test_layout_and_semantic_exclusions()->void:
	var base_path:=native_variant("base",Image.FORMAT_RGBA8)
	var variants:Array[Dictionary]=[
		{"label":"float_format","path":native_variant("float_format",Image.FORMAT_RGBAF)},
		{"label":"mip_chain","path":native_variant("mip_chain",Image.FORMAT_RGBA8,true)},
		{"label":"changed_pixels","path":native_variant("changed_pixels",Image.FORMAT_RGBA8,false,true)},
		{"label":"unknown_metadata","path":native_variant("unknown_metadata",Image.FORMAT_RGBA8,false,false,true)},
		{"label":"local_to_scene","path":native_variant("local_to_scene",Image.FORMAT_RGBA8,false,false,false,true)}]
	for variant:Dictionary in variants:
		var base:=open_variant(base_path);var candidate:=open_variant(variant.path)
		if base.is_empty() or candidate.is_empty():
			release_read(base);release_read(candidate);continue
		var base_texture:Texture2D=texture_of(base.scene);var alternate:Texture2D=texture_of(candidate.scene)
		var base_image:=base_texture.get_image();var alternate_image:=alternate.get_image()
		check(base_image.get_format()==Image.FORMAT_RGBA8 and not base_image.has_mipmaps(),variant.label+": independently reloaded baseline retains the exact image layout")
		if variant.label=="float_format":check(alternate_image.get_format()==Image.FORMAT_RGBAF,"format fixture really retains float pixels after native save/reopen")
		elif variant.label=="mip_chain":check(alternate_image.has_mipmaps(),"mip fixture really retains its complete mip chain after native save/reopen")
		elif variant.label=="changed_pixels":check(base_image.get_data()!=alternate_image.get_data(),"changed-pixel fixture really differs after native save/reopen")
		elif variant.label=="unknown_metadata":check(alternate.get_meta("author_identity","")=="preserve","unknown metadata really survives native save/reopen")
		elif variant.label=="local_to_scene":check(alternate.resource_local_to_scene,"local-resource semantics really survive native save/reopen")
		base_image=null;alternate_image=null
		check(base_texture!=alternate,variant.label+": incompatible texture identity or semantics never merges")
		if variant.label in ["unknown_metadata","local_to_scene"]:
			check(base_texture.get_meta(Textures.PIXEL_KEY)==alternate.get_meta(Textures.PIXEL_KEY),variant.label+": equal pixels/stamped keys cannot bypass the semantic exclusion")
		else:
			check(base_texture.get_meta(Textures.PIXEL_KEY)!=alternate.get_meta(Textures.PIXEL_KEY),variant.label+": actual reloaded image layout/content has a different key")
		var base_ref:WeakRef=weakref(base_texture);var alternate_ref:WeakRef=weakref(alternate)
		base_texture=null;alternate=null
		release_read(base);release_read(candidate)
		check(base_ref.get_ref()==null and alternate_ref.get_ref()==null,variant.label+": no helper-owned texture survives resource cleanup")

func run()->void:
	if DisplayServer.get_name()=="headless":
		check(false,"real GPU renderer required; use run_godot_background.py");quit(1);return
	var was_enabled:=Textures.enabled
	test_folder=Paths.cache_directory("model_texture_sharing_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(test_folder)
	var a:=test_folder.path_join("one.glb");var b:=test_folder.path_join("two.glb")
	textured_glb(a,false);textured_glb(b,true)
	var a_sha:=FileAccess.get_sha256(a);var b_sha:=FileAccess.get_sha256(b)
	check(Embedded.can_copy(a) and Embedded.can_copy(b),"two temporary GLBs are self-contained")
	var built_a:=Compiled.build(a);var built_b:=Compiled.build(b)
	check(built_a.get("ok",false) and built_b.get("ok",false),"production offline compiler builds both real textured native products")
	if not built_a.get("ok",false) or not built_b.get("ok",false):
		print({"one":built_a,"two":built_b});Textures.enabled=was_enabled;quit(1);return
	test_compiled_pair(a,b)
	await test_worker_handoff(a,b)
	test_layout_and_semantic_exclusions()
	check(FileAccess.get_sha256(a)==a_sha and FileAccess.get_sha256(b)==b_sha,"all production handoffs preserve both temporary GLB sources")
	check(Textures._textures.values().all(func(reference:WeakRef)->bool:return reference.get_ref()==null),"weak pool retains no live texture after all test owners are released")
	Textures.enabled=was_enabled
	print("MODEL_TEXTURE_SHARING_GPU checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
