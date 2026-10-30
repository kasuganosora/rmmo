extends "res://tools/test_prefab_spec_preparation.gd"
## Independent oracle for textured native prefab projection. All images live in
## a temporary external runtime cache and the renderer runs on a private desktop.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const SchedulerFixture=preload("res://tools/test_deferred_ready_progress.gd")
class Errors extends Logger:
	var errors:Array[String]=[]
	func _log_error(function:String,_file:String,_line:int,code:String,rationale:String,_editor_notify:bool,_type:int,_backtraces:Array)->void:
		errors.append(function+": "+code+" "+rationale)

func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	check(DisplayServer.get_name()!="headless","real renderer is present")
	if DisplayServer.get_name()=="headless":quit(1);return
	var logger:=Errors.new();OS.add_logger(logger)
	Policy.verify_packages=false;Controls.discard_map_textures=false
	direct=load("res://scripts/world3d/prefab_spec_preparation.gd")
	document=Doc.new();document.load_immutable_records=true;document.load_texture_checks={}
	var folder:=Paths.cache_directory("textured_prefab_specs_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var paths:Array[String]=[]
	for i:int in 3:
		var path:=folder.path_join("pixels_%d.png"%i);paths.append(path)
		var image:=Image.create(19,13,false,Image.FORMAT_RGBA8)
		for y:int in 13:
			for x:int in 19:image.set_pixel(x,y,Color(float((x+i)%7)/6.,float((y+i)%5)/4.,float((x+y+i)%9)/8.,.4 if x<4 else 1.))
		check(image.save_png(path)==OK,"write external textured fixture "+str(i))
	var paint:Dictionary={"name":"textured direct spec","color":[1.,1.,1.,1.],"roughness":.8,"texture_path":paths[0],"normal_path":paths[1],"normal_format":"directx","roughness_path":paths[2],"ao_path":paths[0]}
	var data:=fixture();var arrays:Array=data.meshes[0].surfaces[0]
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN])
	data.materials=[{"paint":paint,"cull":0},{"values":{"albedo_color":Color(.2,.3,.7),"roughness":.6}}]
	var second:Array=arrays.duplicate(true);second[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(0,2,0),Vector3(3,2,0),Vector3(0,2,-4)])
	data.meshes[0].surfaces.append(second);data.meshes[0].materials=[0,1]
	data.meshes[0].bounds=AABB(Vector3(0,0,-4),Vector3(3,2,4))
	data.meshes.append(data.meshes[0].duplicate(true));data.entries[0][1]=[0,1]
	var value:=record(encode(data),"textured_direct")
	value.position=[31.999,-2.25,-32.001];value.rotation=[13.,-33.,7.]
	value.building={"id":"native_house","floor":2,"floor_y":6.,"role":"roof_tiles","part":"wing/baked_roof"}
	var entry:=prepared(value)
	check(direct.supports(value,entry,false,true),"textured immutable native prefab is eligible for direct projection")
	compare(value,entry,"textured multi-slot rotated roof")
	for mode:String in ["none","walk","block"]:
		var leaf:=value.duplicate(true);leaf.uuid="textured_leaf_"+mode;leaf.collision=mode
		leaf.fixture={"id":"door","kind":"door","pivot":[-.7,.3,.2],"angle":-97.,"open":.625}
		compare(leaf,entry,"textured moving leaf "+mode)
	var original:=old_projection(value,317);var candidate:=projection(value,entry,317)
	var map:=Node3D.new();root.add_child(map)
	var old_visual:MeshInstance3D=Stream._spawn(map,original.specs[0]);var new_visual:MeshInstance3D=Stream._spawn(map,candidate.specs[0])
	RenderingServer.force_sync()
	check(old_visual.mesh==new_visual.mesh and old_visual.mesh.get_surface_count()==2,"both real spawns reuse the same two-slot rendered mesh owner")
	for slot:int in 2:
		check(old_visual.mesh.surface_get_material(slot)==new_visual.mesh.surface_get_material(slot) and new_visual.mesh.surface_get_material(slot)==entry.mesh.materials[slot],"real spawn retains canonical material owner slot "+str(slot))
	var material:StandardMaterial3D=entry.mesh.materials[0]
	check(material!=null and material.albedo_texture!=null and material.normal_texture!=null and material.roughness_texture!=null and material.ao_texture==material.albedo_texture and material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"alpha, normal, roughness and shared albedo texture remain bound")
	check(original.specs[0].collision_mesh==entry.source and candidate.specs[0].collision_mesh==entry.source,"both paths retain the same independent collision owner")
	old_visual.free();new_visual.free();map.free();original.dispose();candidate.dispose()
	for test_case:Array in [[true,true,false],[true,false,false],[false,true,false],[true,true,true]]:
		scheduler_case(value,entry,test_case[0],test_case[1],test_case[2])
	for old:bool in [true,false,false,true]:trials.append(benchmark(value,entry,old,2048))
	scheduler_owner_cases(value,entry,paint)
	OS.remove_logger(logger);check(logger.errors.is_empty(),"no engine or script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	print("TEXTURED_PREFAB_SPEC_PREPARATION ",JSON.stringify({"checks":checks,"failures":failures,"trials":trials}))
	for path:String in paths:DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(folder)
	quit(1 if failures else 0)

func scheduler_case(value:Dictionary,entry:Dictionary,immutable:bool,trusted:bool,streamed_owners:bool)->void:
	Policy.verify_packages=not trusted
	document.load_immutable_records=immutable
	var fixture_owner:=SchedulerFixture.new();var f:Dictionary=fixture_owner.fixture(2,false,root)
	var queue:Node=f.service;queue._doc=document
	var item:Dictionary=queue._demanded_by_path["reference:building:0"][0]
	var uuid:String=item.record.uuid
	item.record.merge(value,true);item.record.uuid=uuid
	var job:Dictionary=queue._jobs[item.path]
	if streamed_owners:job.streamed_texture_owners={};job.streamed_texture_scope={}
	queue._publish_ready(Time.get_ticks_usec()-1000000)
	var selected:bool=int(queue.profile.get("native_prefab_direct_instances",0))==1
	var expected:bool=immutable and trusted
	check(selected==expected,"actual scheduler direct selection immutable=%s trusted=%s streamed=%s"%[immutable,trusted,streamed_owners])
	var staged:Dictionary=job.get("staged",{}).get(uuid,{})
	var matches:bool=staged.has("specs") and staged.specs.size()==1
	if matches:
		var spec:Dictionary=staged.specs[0]
		# Editable document effects may restore and recapture a separate CPU
		# render wrapper; the immutable path must keep the canonical owner.
		matches=spec.mesh is Cpu and (spec.mesh==entry.mesh if immutable else spec.mesh.surfaces==entry.mesh.surfaces and spec.mesh.materials==entry.mesh.materials) and spec.collision_mesh==entry.source
	check(matches,"scheduler retains the correct render data/material and collision owners across direct/fallback path")
	f.map.free();fixture_owner.free()
	Policy.verify_packages=false;document.load_immutable_records=true

func scheduler_owner_cases(value:Dictionary,entry:Dictionary,paint:Dictionary)->void:
	var Paint=Cook.Paint
	var key:String=Paint.definition_texture_key(paint,"texture_path")
	var path:String=Paint.texture_source_path(key)
	var texture:Texture2D=entry.mesh.materials[0].albedo_texture
	var digest:String=texture.get_meta("runtime_source_sha256","")
	check(not digest.is_empty(),"scoped scheduler fixture owns an actual versioned texture")
	for mode:String in ["current","stale","replacement"]:
		var fixture_owner:=SchedulerFixture.new();var f:Dictionary=fixture_owner.fixture(2,false,root)
		var queue:Node=f.service;queue._doc=document
		var item:Dictionary=queue._demanded_by_path["reference:building:0"][0]
		var uuid:String=item.record.uuid;item.record.merge(value,true);item.record.uuid=uuid
		var job:Dictionary=queue._jobs[item.path]
		var owners:Dictionary={key:texture}
		var packet:Dictionary={"resident_textures":{key:{"texture":texture,"source_sha":digest}},"sources":{path:digest}}
		var replacement:Texture2D
		if mode=="stale":packet.sources[path]=digest+"stale"
		elif mode=="replacement":
			var pixels:=Image.create(19,13,false,Image.FORMAT_RGBA8);pixels.fill(Color(.1,.8,.3,.6))
			var next_digest:String=pixels.get_data().hex_encode().sha256_text()
			pixels.set_meta("runtime_source_sha256",next_digest)
			replacement=ImageTexture.create_from_image(pixels);replacement.set_meta("runtime_source_sha256",next_digest)
			Paint._textures.erase(key);Paint._texture_refs.erase(key)
			packet={"images":{key:pixels},"uploaded_textures":{key:replacement},"sources":{path:next_digest}}
			owners={key:replacement}
			# A changed generation must republish from the real admitted CPU
			# packet before instance projection, exactly as the loader does.
			document.load_material_pool={}
			job.result.prefab_cpu={value.house_prefab.sha256:House.prepare_cpu(value)}
		job.streamed_texture_owners=owners;job.streamed_texture_scope={};job.result.prefab_texture_packet=packet
		var before_images:Dictionary=Paint.prepared_images;var before_uploads:Dictionary=Paint.prepared_textures
		for step in 16:
			queue._publish_ready(Time.get_ticks_usec()-1000000)
			if job.get("staged",{}).has(uuid) or queue.instance_errors.has(uuid):break
		var staged:Dictionary=job.get("staged",{}).get(uuid,{})
		check(is_same(Paint.prepared_images,before_images) and is_same(Paint.prepared_textures,before_uploads),mode+" restores both synchronous texture scopes")
		if mode=="stale":
			check(staged.is_empty() and queue.instance_errors.has(uuid) and int(queue.profile.get("native_prefab_direct_instances",0))==0,"stale texture ticket cannot bypass generation rejection through direct projection")
		else:
			check(staged.has("specs") and staged.specs.size()==1,mode+" stages one complete private prefab")
			if staged.has("specs") and staged.specs.size()==1:
				var spec:Dictionary=staged.specs[0]
				check(spec.mesh.materials[0].albedo_texture==(replacement if mode=="replacement" else texture),mode+" adopts the actual handed-off texture owner")
				check(spec.mesh==House._meshes[value.house_prefab.sha256].mesh,mode+" uses the canonical prefab owner after entering the scope")
			check(int(queue.profile.get("native_prefab_direct_instances",0))==1,mode+" projects the current canonical prefab directly")
			if mode=="replacement":check(entry.mesh.materials[0].albedo_texture==texture,"replacement leaves earlier live prefab owners untouched")
		f.map.free();fixture_owner.free()
