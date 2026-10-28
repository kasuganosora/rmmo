extends "res://tools/test_editor_terrain_texture_scope.gd"
## Real 3D HTTP + UI-shared surface transactions and mutable editor texture
## reload. Run in a private graphics desktop with an isolated content root.
## Do not set Policy.verify_packages: this exercises the normal editor policy.

func color_at(texture:Texture2D)->Color:
	if texture==null:return Color.TRANSPARENT
	var image:Image=texture.get_image()
	return Color.TRANSPARENT if image==null or image.is_empty() else image.get_pixel(0,0)

func fixture_sha(bytes:PackedByteArray)->String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes)
	return context.finish().hex_encode()

func fixture_put(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()

func fixture_dds()->PackedByteArray:
	# Complete 4x4 -> 2x2 -> 1x1 DXT1 chain, red blocks, same PNG dimensions.
	var data:=PackedByteArray();data.resize(128+3*8)
	for i:int in 4:data[i]="DDS ".to_ascii_buffer()[i];data[84+i]="DXT1".to_ascii_buffer()[i]
	data.encode_u32(4,124);data.encode_u32(8,0x000A1007);data.encode_u32(12,4);data.encode_u32(16,4)
	data.encode_u32(28,3);data.encode_u32(76,32);data.encode_u32(80,4);data.encode_u32(108,0x401008)
	for offset:int in range(128,data.size(),8):data.encode_u16(offset,0xf800);data.encode_u16(offset+2,0xf800)
	return data

func publish_fixture_dds(path:String)->void:
	var source:=FileAccess.get_file_as_bytes(path);var bytes:=fixture_dds();var target:=path+".dxt1.dds"
	fixture_put(target,bytes)
	fixture_put(target+".source.json",JSON.stringify({"version":1,"encoder_version":1,"source_sha256":fixture_sha(source),"source_bytes":source.size(),"dds_sha256":fixture_sha(bytes),"dds_bytes":bytes.size(),"normal":false,"flip":false}).to_utf8_buffer())

func compressed_texture(texture:Texture2D)->bool:
	return texture!=null and texture.get_image()!=null and texture.get_image().is_compressed()

func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	Engine.max_fps=60
	var isolated_root:=OS.get_environment("RMMO_MATERIAL_HTTP_TEST_ROOT")
	var asset_manager:=root.get_node_or_null("AssetManager")
	if isolated_root.is_empty() or not isolated_root.is_absolute_path() or not DirAccess.dir_exists_absolute(isolated_root) or asset_manager==null:
		check(false,"runner must provide an existing absolute isolated content root")
		quit(1);return
	asset_manager.content_root_override=isolated_root
	check(Paths.external_root().replace("\\","/").simplify_path()==isolated_root.replace("\\","/").simplify_path(),"editor fixture uses isolated content root")
	check(Prepare.TextureCache.Policy.trusted() and not Prepare.TextureCache.Policy.verify_packages,"editor uses default trusted package policy")
	var directory:=Paths.cache_directory("material_http_trusted_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var texture_path:=directory.path_join("mutable.png")
	var image:=Image.create(4,4,false,Image.FORMAT_RGBA8)
	image.fill(Color.RED);check(image.save_png(texture_path)==OK,"write first authoring texture")
	var definition:={"name":"Editable texture","color":[1.,1.,1.,1.],"roughness":.8,"texture_path":texture_path}
	var doc:=Doc.new()
	var terrain_id:String=doc.add_box("grass",Vector3.ZERO,Vector3(8,1,8))
	setup_record(doc,terrain_id,definition)
	var box_id:String=doc.add_box("block",Vector3(12,1,0),Vector3(2,2,2))
	var path:=directory.path_join("map.gltf")
	check(doc.save(path)==OK,"save isolated editable map")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start real 3D HTTP endpoint")
	await call_tool("open_world",{"path":path})
	var original_material:ShaderMaterial=editor._view.get_node(terrain_id).get_active_material(0) as ShaderMaterial
	var original_texture:Texture2D=base_texture(terrain_id)
	check(original_texture!=null and color_at(original_texture).r>.9,"first load renders original red pixels")
	var faces:Dictionary=await call_tool("list_object_surfaces",{"id":box_id})
	var rows:Array=faces.get("faces",[])
	check(not rows.is_empty(),"HTTP enumerates paint targets")
	if not rows.is_empty():
		var target:Dictionary=rows[0].target
		var before:Array=editor._doc.records.duplicate(true)
		var undo_before:int=editor._doc._undo.size()
		await call_tool("paint_surface",{"id":box_id,"target":target,"material_id":"builtin:white"})
		check(editor._doc._find(box_id).get("surface_paint",[]).size()==1 and editor._doc._undo.size()==undo_before+1,"HTTP paint uses shared single undo transaction")
		var painted:Array=editor._doc.records.duplicate(true)
		await call_tool("undo")
		check(equivalent(editor._doc.records,before),"HTTP undo restores pre-paint document")
		await call_tool("redo")
		check(equivalent(editor._doc.records,painted),"HTTP redo restores paint")
		await call_tool("clear_surface_material",{"id":box_id,"target":target})
		check(not editor._doc._find(box_id).has("surface_paint"),"HTTP clear removes the surface override")
		await call_tool("undo")
		check(equivalent(editor._doc.records,painted),"undo of clear restores the same painted face")
		await call_tool("redo")
		check(not editor._doc._find(box_id).has("surface_paint"),"redo of clear removes the override again")
		await call_tool("undo")
		await call_tool("set_object_properties",{"ids":[box_id],"locked":true})
		var locked:Array=editor._doc.records.duplicate(true)
		var locked_undo:int=editor._doc._undo.size()
		await call_tool("paint_surface",{"id":box_id,"target":target,"material_id":"builtin:checker"},false)
		await call_tool("clear_surface_material",{"id":box_id},false)
		check(equivalent(editor._doc.records,locked) and editor._doc._undo.size()==locked_undo,"locked paint and clear reject with no document or undo changes")
		await call_tool("set_object_properties",{"ids":[box_id],"locked":false})
		await call_tool("save_world")
		var saved:Array=editor._doc.records.duplicate(true)
		await call_tool("open_world",{"path":path})
		check(equivalent(editor._doc.records,saved) and editor._doc._find(box_id).get("surface_paint",[]).size()==1,"HTTP save and reopen preserve painted face")
	# The source PNG is unchanged. A newly certified compressed representation
	# must replace the cached raw texture without changing the live old owner.
	publish_fixture_dds(texture_path)
	await call_tool("open_world",{"path":path})
	var compressed_owner:Texture2D=base_texture(terrain_id)
	check(compressed_texture(compressed_owner) and compressed_owner!=original_texture,"new DDS representation replaces a live PNG texture of the same source")
	check(not compressed_texture(original_texture) and color_at(original_texture).r>.9,"previous PNG owner remains live and unchanged")
	# Removing provenance requires the next generation to fall back to PNG even
	# though the logical source SHA still matches the prior compressed texture.
	DirAccess.remove_absolute(texture_path+".dxt1.dds.source.json")
	await call_tool("open_world",{"path":path})
	var fallback_owner:Texture2D=base_texture(terrain_id)
	check(fallback_owner!=null and not compressed_texture(fallback_owner) and fallback_owner!=compressed_owner,"expired DDS metadata selects PNG despite matching source SHA")
	check(compressed_texture(compressed_owner),"old compressed owner remains intact after PNG fallback")
	Paint._textures.erase(texture_path)
	var weak:Variant=Paint._texture_refs.get(texture_path)
	check(weak!=null and weak.get_ref()==fallback_owner,"evicted PNG remains discoverable through the weak cache")
	publish_fixture_dds(texture_path)
	await call_tool("open_world",{"path":path})
	var weak_replacement:Texture2D=base_texture(terrain_id)
	check(compressed_texture(weak_replacement) and weak_replacement!=fallback_owner,"weak PNG alias cannot hide the new DDS representation")
	check(not compressed_texture(fallback_owner) and color_at(fallback_owner).r>.9,"weakly retained PNG owner remains unchanged")
	# Keep the old material and texture live during an ordinary trusted reload.
	# Distinct pixels are checked directly, not just path-derived identity metadata.
	image.fill(Color.BLUE);check(image.save_png(texture_path)==OK,"rewrite pixels at the same authoring path")
	await call_tool("open_world",{"path":path})
	var next_texture:Texture2D=base_texture(terrain_id)
	check(next_texture!=null and next_texture!=original_texture and color_at(next_texture).b>.9,"same-path reload publishes fresh blue pixels")
	check(original_material!=null and original_material.get_shader_parameter("base_albedo")==original_texture and color_at(original_texture).r>.9,"old live material and pixels remain unchanged")
	# Start the real load again and exit after its preparation has an admitted
	# lease. Detached workers must release that exact ledger via the drainer.
	var pending:Dictionary=await call_tool("open_world",{"path":path,"background":true})
	check(pending.get("pending",false),"HTTP background load starts for exit cancellation")
	var queue:Node
	for i in 600:
		if is_instance_valid(editor._load_job._preparation):
			queue=editor._load_job._preparation
			queue.pump()
			if queue.ledger.count()>0:break
		await process_frame
	var ledger:RefCounted=queue.ledger if is_instance_valid(queue) else null
	check(ledger!=null and ledger.count()>0 and ledger.reserved_bytes>0,"real texture load holds a nonzero admission lease before exit")
	var owned_workers:Array=[]
	if is_instance_valid(queue):
		for row:Dictionary in queue.rows.values():
			if row.has("worker"):owned_workers.append(row.worker)
	var drainer:Node=root.get_node_or_null("AssetWorkerDrainer")
	editor.queue_free();await process_frame
	for i in 600:
		if ledger==null or ledger.count()==0:break
		await process_frame
	check(ledger!=null and ledger.count()==0 and ledger.reserved_bytes==0,"exit cancellation eventually releases the admitted load budget")
	var remaining:=0
	if is_instance_valid(drainer):
		for job:Dictionary in drainer.jobs:
			if owned_workers.has(job.worker):remaining+=1
	check(remaining==0,"exit cancellation drains this operation's detached workers")
	print("EDITOR_MATERIAL_HTTP_TRUSTED_FAILED=",failed)
	quit(1 if failed else 0)
