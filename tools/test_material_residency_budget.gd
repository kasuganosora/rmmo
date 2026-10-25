extends SceneTree
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Slices=preload("res://scripts/world3d/material_publication.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func settle()->void:
	RenderingServer.force_sync()
	# Renderer statistics lag resource destruction by the frames in flight.
	for i in 16:await RenderingServer.frame_post_draw
	await create_timer(1.1).timeout
func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	var dir:=Paths.cache_directory("material_residency_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(dir)
	Paint._textures.clear();Paint._materials.clear();Paint.prepared_images.clear();Paint.residency_budget_enabled=false
	var definitions:Array=[];var textures:Array[WeakRef]=[];var keep:StandardMaterial3D
	for i in 16:
		var image:=Image.create(512,512,false,Image.FORMAT_RGBA8);image.fill(Color(float(i)/16,.4,.2,1));image.generate_mipmaps()
		var path:=dir.path_join("%d.png"%i);image.save_png(path);image.set_meta("runtime_source_sha256",FileAccess.get_sha256(path))
		Paint.prepare_images({path:image})
		var definition:={"name":"cache_%d"%i,"color":[1.,1.,1.,1.],"roughness":.9,"tile_size":[2.,2.],"texture_path":path};definitions.append(definition)
		var material:=Paint.make_material(definition);textures.append(weakref(material.albedo_texture))
		if i==0:keep=material
	await settle();var before:=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
	Paint.residency_budget_enabled=true;Paint.cache_byte_budget=4*1024*1024
	var trimmed:=Paint.trim_cached_resources();await settle()
	var after:=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED);var alive:=0
	for ref:WeakRef in textures:
		if ref.get_ref()!=null:alive+=1
	check(trimmed.after_bytes<=Paint.cache_byte_budget,"unique hot-cache texture footprint obeys byte budget")
	check(alive<16 and after<before,"retiring cache-only resources releases actual renderer texture memory")
	var reused:=Paint.make_material(definitions[0]);check(reused==keep and reused.albedo_texture==textures[0].get_ref(),"live material/texture are reused after strong-cache eviction")
	var image:=Image.create(512,512,false,Image.FORMAT_RGBA8);image.fill(Color.BLUE);image.generate_mipmaps();image.set_meta("runtime_source_sha256","f".repeat(64))
	Paint.prepare_images({definitions[0].texture_path:image})
	var replaced:=Paint.make_material(definitions[0]);check(replaced!=keep and replaced.albedo_texture!=keep.albedo_texture,"changed source digest cannot reuse a weak material/texture ticket")
	check(keep.albedo_texture==textures[0].get_ref(),"active source material remains immutable")
	# A full material may exceed the hot budget. Its job-scoped complete texture
	# handoff must progress even when each hot entry is immediately retired.
	Paint.cache_byte_budget=0;Paint._textures.clear();Paint._materials.clear();Paint._texture_refs.clear();Paint._material_refs.clear()
	var paint:Dictionary=definitions[2].duplicate(true);paint.normal_path=definitions[3].texture_path
	var slot:={"paint":paint,"cull":0};var pool:Dictionary={};var tickets:Dictionary={};var turns:=0
	while not pool.has([slot]) and turns<8:
		Slices.step([slot],{},pool,tickets);Paint.trim_cached_resources();turns+=1
	check(pool.has([slot]) and turns==3 and tickets.is_empty(),"job-scoped complete textures finish one-slot-per-turn publication even with zero hot budget")
	check(Paint._textures.is_empty() and Paint._materials.is_empty(),"published live material survives without any strong hot-cache residency")
	tickets["previous_turn"]=pool[[slot]].albedo_texture
	check(Slices.step([slot],{},pool,tickets)==Slices.READY and tickets.is_empty(),"already-completed shared material also clears an obsolete handoff")
	var report:={"failures":failures,"checks":8,"renderer_texture_before":before,"renderer_texture_after":after,"alive_textures":alive,"trim":trimmed,"zero_budget_material_turns":turns}
	var output:="D:/code/rmmo_runtime/review_artifacts/editor_runtime_followup_20261017/material_residency.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("MATERIAL_RESIDENCY ",JSON.stringify(report));quit(1 if failures else 0)
