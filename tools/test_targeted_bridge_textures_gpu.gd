extends "res://tools/test_targeted_bridge_textures.gd"
## Real GPU owners and the actual admitted worker packet -> House -> Paint path.
## Run only through run_godot_background.py; creates private fixture assets.
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")

func tickets(count:int)->void:
	check(DisplayServer.get_name()!="headless","targeted texture publication uses real renderer")
	Paint._textures.clear();Paint._materials.clear();Prefab._meshes.clear();Prefab._render_meshes.clear()
	for i:int in count:
		var image:=Pixels.image(paths[i],false)
		check(image!=null,"resident source has real pixels %d"%i)
		if image==null:continue
		var texture:=ImageTexture.create_from_image(image)
		texture.set_meta("runtime_source_sha256",image.get_meta("runtime_source_sha256",""))
		Paint._textures[paths[i]]=texture

func wait_ready(queue:Queue)->Dictionary:
	var job:Dictionary=await super.wait_ready(queue)
	if job.is_empty() or not job.result.get("error","").is_empty():return job
	var packet:Dictionary=job.result.prefab_texture_packet
	packet.resident_textures=job.pixel_tickets.duplicate()
	var record:Dictionary=job.result.records[0]
	var previous:Dictionary=Paint.prepared_images.duplicate()
	var timings:Dictionary={}
	check(Prefab.publish_prepared(record,job.result.prefab_cpu[record.house_prefab.sha256],{},queue._doc.load_material_pool,timings,packet),"actual bridge worker packet publishes all three real materials")
	var mesh:Mesh=Prefab.geometry(record).mesh
	var actual:Dictionary={}
	for material:Material in mesh.materials:
		var definition:Dictionary=material.get_meta("runtime_paint_definition",{})
		for field:String in Prefab.TEXTURE_PROPERTIES:
			var path:String=definition.get(field,"")
			if path.is_empty():continue
			var texture:Texture2D=material.get(Prefab.TEXTURE_PROPERTIES[field])
			check(texture!=null,"published material binds "+path.get_file())
			if texture==null:continue
			actual[path]=texture
			if job.pixel_tickets.has(path):
				check(texture==job.pixel_tickets[path].texture,"resident texture reused without upload "+path.get_file())
			elif packet.images.has(path):
				var image:Image=packet.images[path]
				check(fixture.canonical(texture.get_image())==fixture.canonical(image),"prepared image and every mip survive actual upload "+path.get_file())
	check(actual.size()==11,"all eleven declared sources have real material consumers")
	check(Paint.prepared_images==previous,"synchronous publication restores previous prepared-image ownership")
	print("TARGETED_BRIDGE_GPU parts_ms=",timings," prepared=",packet.images.size()," resident=",job.pixel_tickets.size())
	return job
