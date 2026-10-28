extends "res://tools/test_streamed_texture_publication.gd"
## A real reference worker and DeferredAssetLoader publish the same temporary
## terrain as the ordinary source route, including a cold return/zero hot cache.
const Native=preload("res://scripts/world3d/streamed_texture_source.gd")

func run()->void:
	var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.substr(9)
	if output.is_empty() or not check_gpu():quit(2);return
	var logger:=Errors.new();OS.add_logger(logger)
	Pixels.Policy.verify_packages=false
	files=Files.new();files.content_root=Prep.Paths.external_root();files.folder=output.get_base_dir()
	var path:String=files.folder.path_join("terrain_source.png")
	var image:=Image.create(64,64,false,Image.FORMAT_RGBA8);image.fill(Color(.3,.7,.2,1.))
	check(image.save_png(path)==OK,"save isolated terrain source")
	var sha:=FileAccess.get_sha256(path);image.generate_mipmaps()
	var writer:=Thread.new();writer.start(Native.publish.bind(path,image,sha,"source",files.content_root))
	while writer.is_alive():await process_frame
	check(writer.wait_to_finish()==OK,"native terrain product published before reference load")
	var helper:=TerrainFixture.new();var record:Dictionary=helper.fixture("native_terrain",0);helper.free()
	record.collision="none"
	record.terrain_material={"name":"native terrain","color":[1.,1.,1.,1.],"roughness":.8,"tile_size":[1.,1.],"texture_path":path,"height_path":path}
	await native_case(record,false)
	await native_case(record,true)
	check(FileAccess.get_sha256(path)==sha,"reference tests preserve source bytes")
	clear_caches();files.free();OS.remove_logger(logger)
	check(logger.errors.is_empty(),"zero engine/script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"checks":passed+failed,"failures":failed}));file.close()
	quit(1 if failed else 0)

func native_case(record:Dictionary,zero_budget:bool)->void:
	var label:="zero cache return" if zero_budget else "initial reference"
	clear_caches()
	var expected:Dictionary=declared(record)
	var stored:Dictionary=files.fixture("native_reference_"+str(zero_budget),[record])
	check(not stored.is_empty(),label+": save temporary native references")
	var index:Dictionary=Index.build(stored.path,files.content_root,[record])
	check(index.ok,label+": dependency index built")
	var helper:=References.new();var entries:Array=helper.entries(index,[0]);helper.free()
	var plan:Dictionary=Prep.estimate(index.rows[0].prefab_textures,files.content_root)
	check(plan.rows.size()==1 and plan.rows.values()[0].extension=="stex",label+": color and shader height share one native plan")
	var worker:=Thread.new();worker.start(Chunk.prepare.bind(index,entries,stored.path,files.content_root,null,null,plan))
	while worker.is_alive():await process_frame
	var prepared:Dictionary=worker.wait_to_finish()
	check(prepared.error.is_empty() and prepared.surface_arrays.has(record.uuid),label+": real worker prepares geometry")
	var packet:Dictionary=prepared.get("prefab_texture_packet",{})
	check(packet.get("images",{}).is_empty() and packet.get("uploaded_textures",{}).size()==1,label+": real reference result retains only the completed native texture")
	if not prepared.error.is_empty() or packet.get("uploaded_textures",{}).is_empty():return
	var control:=document();var control_queue:=Deferred.new();control_queue._doc=control;control_queue._accept_prepared_records(prepared);control_queue.free()
	var old:MeshInstance3D=control._mesh(record);old.free()
	var baseline:Array=control.observed;control=null
	clear_caches();var saved_budget:int=Paint.cache_byte_budget
	if zero_budget:Paint.cache_byte_budget=0
	Paint.texture_profile_enabled=true;Pixels.reset_profile()
	var fixtures:=SchedulerFixture.new();var f:Dictionary=fixtures.fixture(1,false,root)
	var queue:Node=f.service;var doc:=document();queue._doc=doc
	var item:Dictionary=queue._demanded_by_path["reference:building:0"][0]
	var current:Dictionary=record.duplicate(true);current.uuid=item.record.uuid;item.record=current
	for field:String in ["surface_arrays","surface_bounds","terrain_contexts"]:
		if prepared.get(field,{}).has(record.uuid):prepared[field][current.uuid]=prepared[field][record.uuid];prepared[field].erase(record.uuid)
	queue._accept_prepared_records(prepared)
	var job:Dictionary=queue._jobs[item.path];job.result=prepared
	var turns:=0
	while doc.calls==0 and turns<20:
		queue._publish_ready(Time.get_ticks_usec()-1000000);turns+=1
		check(Paint.prepared_images.is_empty() and Paint.prepared_textures.is_empty(),label+": both scopes closed after slice")
	var counters:Dictionary=Paint.profile_snapshot().counters
	check(doc.calls==1,label+": actual WorldDocument construction completes")
	check(counters.get("paint.texture.runtime_image_lookup",0)==0 and counters.get("paint.texture.upload_bytes",0)==0,label+": no source lookup or duplicate upload during actual publication")
	check(counters.get("paint.texture.texture_only_handoffs",0)==1,label+": one native handoff serves both material roles")
	check(doc.load_material_pool.is_empty(),label+": shader-only terrain creates no unused StandardMaterials")
	RenderingServer.force_sync()
	check(material_fingerprints(baseline)==material_fingerprints(doc.observed),label+": material/height pixels and mip chains equal the ordinary source route")
	# Fingerprinting reads complete data for verification only, after the work
	# counters above. StreamedTexture2D.get_image is never used by publication.
	f.map.free();fixtures.free();baseline.clear();doc=null;prepared.clear();packet.clear();job.clear()
	Paint.cache_byte_budget=saved_budget;clear_caches();Drainer.synchronize_transfer()
