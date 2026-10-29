extends RefCounted
## Offline split-native publication. Materials keep every authored parameter,
## but their texture slots become scalar bindings instead of native dependencies.
## Pixel products are immutable and shared by complete pixel/layout identity.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Product=preload("res://scripts/world3d/streamed_texture_product.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const VERSION:=1
const BINDINGS_META:=&"rmmo_model_texture_bindings_v1"
const TABLE_META:=&"rmmo_model_texture_table_v1"
const NORMAL_SLOTS:=["normal_texture","detail_normal","bent_normal_texture"]
const TEXTURE_METADATA:=[&"compiled_model_pixel_key_v1",&"compiled_grass_pixel_key"]
const MAX_JSON_INTEGER:=9007199254740991

static func directory(root:String)->String:
	return root.path_join("cache/world3d/model_textures_v1")

static func table_directory(root:String)->String:
	return root.path_join("cache/world3d/compiled_assets_v1/texture_tables_v1")

static func _sha(value:Variant)->bool:
	if not value is String or value.length()!=64:return false
	for character in value:
		if character not in "0123456789abcdef":return false
	return true

static func _integer(value:Variant,maximum:int,minimum:int=0)->bool:
	return (value is int or value is float) and is_finite(value) and value>=minimum and value<=maximum and value==int(value)

static func _failed(message:String,code:Error=ERR_INVALID_DATA)->Dictionary:
	return {"ok":false,"error":message,"error_code":code,"table":{}}

static func _cancelled(token:RefCounted)->bool:
	return token!=null and token.is_cancelled()

static func _pixel_key(image:Image)->String:
	# Identical to the existing offline stamp; a name or material role does not
	# duplicate an unchanged pixel product. Normal mip generation happened earlier.
	var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256)
	hash_.update(var_to_bytes([1,image.get_width(),image.get_height(),image.get_format(),image.has_mipmaps()]))
	hash_.update(image.get_data())
	return hash_.finish().hex_encode()

static func _collect(scene:Node)->Dictionary:
	if scene==null or not is_instance_valid(scene):return _failed("missing_scene")
	if scene.has_meta(TABLE_META):return _failed("already_split",ERR_ALREADY_EXISTS)
	var pending_nodes:Array[Node]=[scene];var pending_materials:Array[Material]=[]
	while not pending_nodes.is_empty():
		var node:Node=pending_nodes.pop_back()
		pending_nodes.append_array(node.get_children())
		if not node is MeshInstance3D:continue
		pending_materials.append(node.material_override);pending_materials.append(node.material_overlay)
		if node.mesh==null:continue
		for surface:int in node.mesh.get_surface_count():
			pending_materials.append(node.mesh.surface_get_material(surface))
			pending_materials.append(node.get_surface_override_material(surface))
	var materials:Array=[];var seen:Dictionary={};var textures:Dictionary={};var slots:=0
	while not pending_materials.is_empty():
		var material:Material=pending_materials.pop_back()
		if material==null or seen.has(material.get_instance_id()):continue
		seen[material.get_instance_id()]=true
		if not material is StandardMaterial3D or material.get_script()!=null:return _failed("unsupported_material")
		if material.has_meta(BINDINGS_META):return _failed("already_split",ERR_ALREADY_EXISTS)
		pending_materials.append(material.next_pass)
		var original:Dictionary={}
		for info:Dictionary in material.get_property_list():
			if not (int(info.usage)&PROPERTY_USAGE_STORAGE):continue
			var value:Variant=material.get(info.name)
			if not value is Texture2D:continue
			# 4.8 beta1 StreamedTexture2D.get_image() reopens the complete file.
			# Consume an existing split product through its table, not a second
			# image read/hash/reconversion hidden in material traversal.
			if not value is ImageTexture or value.get_script()!=null or value.resource_local_to_scene:return _failed("unsupported_texture:"+value.get_class())
			for key:StringName in value.get_meta_list():
				if key not in TEXTURE_METADATA:return _failed("unsupported_texture_metadata:"+str(key))
			original[str(info.name)]=value;textures[value.get_instance_id()]=value;slots+=1
		if not original.is_empty():materials.append({"material":material,"slots":original})
	return {"ok":true,"materials":materials,"textures":textures,"bindings":slots}

static func _image_row(image:Image,id:String)->Dictionary:
	var sizes:Array[int]=[];var total:=image.get_data_size()
	for mip:int in image.get_mipmap_count()+1:
		var start:=image.get_mipmap_offset(mip)
		var end:=image.get_mipmap_offset(mip+1) if mip<image.get_mipmap_count() else total
		sizes.append(end-start)
	return {"file":"cache/world3d/model_textures_v1/"+id+".stex","pixel_sha":id,
		"width":image.get_width(),"height":image.get_height(),"format":image.get_format(),
		"mip_sizes":sizes,"bytes":total,"file_bytes":44+8*sizes.size()+total,
		"alpha":image.detect_alpha()!=Image.ALPHA_NONE,"normal_xy":image.get_format()==Image.FORMAT_RGTC_RG}

static func _stage_image(image:Image,id:String,root:String,token:RefCounted)->Dictionary:
	var destination:=directory(root).path_join(id+".stex")
	if not Paths.allowed(destination,root):return _failed("texture_path",ERR_FILE_BAD_PATH)
	if _cancelled(token):return _failed("cancelled",ERR_SKIP)
	if FileAccess.file_exists(destination):return {"ok":true,"row":{},"reused":true}
	if DirAccess.dir_exists_absolute(destination):return _failed("texture_target_directory",ERR_FILE_BAD_PATH)
	var temporary:=destination+".tmp-%d-%d-%d"%[OS.get_process_id(),OS.get_thread_caller_id(),Time.get_ticks_usec()]
	if not Paths.allowed(temporary,root):return _failed("staging_path",ERR_FILE_BAD_PATH)
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return _failed("texture_write",FileAccess.get_open_error())
	var error:=Product.write(file,image);file.close()
	if error==OK and _cancelled(token):error=ERR_SKIP
	if error!=OK:
		if FileAccess.file_exists(temporary):DirAccess.remove_absolute(temporary)
		return _failed("cancelled" if error==ERR_SKIP else "texture_write",error)
	return {"ok":true,"row":{"staged":temporary,"destination":destination},"reused":false}

static func _cleanup_staged(rows:Array,root:String)->void:
	for row:Dictionary in rows:
		var path:String=row.staged
		if Paths.allowed(path,root) and FileAccess.file_exists(path):DirAccess.remove_absolute(path)

static func _staging_failure(rows:Array,root:String,message:String,error:Error=ERR_INVALID_DATA)->Dictionary:
	_cleanup_staged(rows,root)
	return _failed(message,error)

static func _publish_image(image:Image,id:String,root:String,token:RefCounted)->Dictionary:
	# Keep the previous per-file publication route as an explicit test control.
	var staged:=_stage_image(image,id,root,token)
	if not staged.ok:return staged
	if staged.reused:return {"ok":true,"written":false,"processes":0}
	var error:=Atomic.publish_new(staged.row.staged,staged.row.destination)
	_cleanup_staged([staged.row],root)
	if error not in [OK,ERR_ALREADY_EXISTS]:return _failed("texture_publish",error)
	if error==ERR_ALREADY_EXISTS and not FileAccess.file_exists(staged.row.destination):return _failed("texture_target_directory",ERR_FILE_BAD_PATH)
	return {"ok":true,"written":error==OK,"processes":1}

static func prepare(scene:Node,content_root:String,token:RefCounted=null,batch_publish:bool=true)->Dictionary:
	# This convenience transaction borrows a private offline scene. It reads each
	# ImageTexture once and retains only one readback while publishing. It creates
	# no texture RID, decoder, worker pool, or long-lived image cache.
	if not Thread.is_main_thread():return _failed("main_thread_required",ERR_UNAVAILABLE)
	if content_root.is_empty() or not Paths.allowed(directory(content_root),content_root) or not Paths.allowed(table_directory(content_root),content_root):return _failed("content_root",ERR_FILE_BAD_PATH)
	if _cancelled(token):return _failed("cancelled",ERR_SKIP)
	var gathered:=_collect(scene)
	if not gathered.ok:return gathered
	for folder:String in [directory(content_root),table_directory(content_root)]:
		var error:=DirAccess.make_dir_recursive_absolute(folder)
		if error!=OK:return _failed("product_directory",error)
	var table:Dictionary={"version":VERSION,"textures":{},"image_bytes":0}
	var ids:Dictionary={};var pending:Array=[]
	var stats:Dictionary={"readbacks":0,"pixel_hashes":0,"products_written":0,"products_reused":0,"textures":0,"bindings":gathered.bindings,"image_bytes":0,"file_bytes":0,"product_publish_processes":0,"table_publish_processes":0}
	for object_id:int in gathered.textures:
		if _cancelled(token):return _staging_failure(pending,content_root,"cancelled",ERR_SKIP)
		var texture:ImageTexture=gathered.textures[object_id]
		var image:Image=texture.get_image();stats.readbacks+=1
		if image==null or image.is_empty():return _staging_failure(pending,content_root,"missing_complete_image")
		var id:=_pixel_key(image);stats.pixel_hashes+=1;ids[object_id]=id
		if table.textures.has(id):continue
		var row:=_image_row(image,id)
		var publication:Dictionary
		if batch_publish:
			publication=_stage_image(image,id,content_root,token)
			if publication.ok:
				if publication.reused:stats.products_reused+=1
				else:pending.append(publication.row)
		else:
			publication=_publish_image(image,id,content_root,token)
			if publication.ok:
				stats.products_written+=int(publication.written);stats.products_reused+=int(not publication.written)
				stats.product_publish_processes+=int(publication.processes)
		if not publication.ok:
			_cleanup_staged(pending,content_root);return publication
		table.textures[id]=row;table.image_bytes+=int(row.bytes)
		stats.file_bytes+=int(row.file_bytes)
	# Only paths/metadata survive the per-image loop. A batch never accumulates
	# decoded pixel buffers, and descriptors are withheld on any partial failure.
	if batch_publish:
		var publication:=Atomic.publish_new_batch(pending,content_root,token)
		_cleanup_staged(pending,content_root)
		if not publication.ok:return _failed("cancelled" if publication.error==ERR_SKIP else "texture_publish",publication.error)
		stats.product_publish_processes=int(publication.processes)
		for status:int in publication.results:
			stats.products_written+=int(status==OK);stats.products_reused+=int(status==ERR_ALREADY_EXISTS)
	stats.textures=table.textures.size();stats.image_bytes=table.image_bytes
	# Publish table before changing the graph. Cancellation/failure leaves its
	# original slots intact; only unreachable immutable products may remain.
	var encoded:=JSON.stringify(table,"",true,true).to_utf8_buffer()
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(encoded)
	var table_sha:=context.finish().hex_encode()
	var destination:=table_directory(content_root).path_join(table_sha+".json")
	if not Paths.allowed(destination,content_root):return _failed("table_path",ERR_FILE_BAD_PATH)
	if _cancelled(token):return _failed("cancelled",ERR_SKIP)
	if not FileAccess.file_exists(destination):
		if DirAccess.dir_exists_absolute(destination):return _failed("table_target_directory",ERR_FILE_BAD_PATH)
		var temporary:=destination+".tmp-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
		if not Paths.allowed(temporary,content_root):return _failed("table_staging_path",ERR_FILE_BAD_PATH)
		var file:=FileAccess.open(temporary,FileAccess.WRITE)
		if file==null:return _failed("table_write",FileAccess.get_open_error())
		var wrote:=file.store_buffer(encoded);file.close()
		var error:Error=ERR_FILE_CANT_WRITE if not wrote else (ERR_SKIP if _cancelled(token) else Atomic.publish_new(temporary,destination))
		stats.table_publish_processes=int(wrote and error!=ERR_SKIP)
		if FileAccess.file_exists(temporary):DirAccess.remove_absolute(temporary)
		if error not in [OK,ERR_ALREADY_EXISTS]:return _failed("cancelled" if error==ERR_SKIP else "table_publish",error)
		if error==ERR_ALREADY_EXISTS and not FileAccess.file_exists(destination):return _failed("table_target_directory",ERR_FILE_BAD_PATH)
	if _cancelled(token):return _failed("cancelled",ERR_SKIP)
	for original:Dictionary in gathered.materials:
		var bindings:Dictionary={};var material:StandardMaterial3D=original.material
		for slot:String in original.slots:
			bindings[slot]={"id":ids[original.slots[slot].get_instance_id()],"normal":slot in NORMAL_SLOTS}
			material.set(slot,null)
		material.set_meta(BINDINGS_META,bindings)
	scene.set_meta(TABLE_META,table_sha)
	var descriptor:Dictionary={"version":VERSION,"sha256":table_sha,"bytes":encoded.size(),"textures":table.textures.size(),"image_bytes":table.image_bytes}
	return {"ok":true,"error":"","table":table,"table_sha":table_sha,"table_bytes":encoded.size(),"table_path":destination,
		"texture_table":descriptor,"stats":stats,"restore":{"scene":scene,"materials":gathered.materials}}

static func restore(prepared:Dictionary)->void:
	# Call after packing/saving or after a later transaction failure. Clear the
	# owner packet so it cannot retain the original graph through a native read.
	var state:Dictionary=prepared.get("restore",{})
	if state.is_empty():return
	assert(Thread.is_main_thread())
	for original:Dictionary in state.get("materials",[]):
		var material:StandardMaterial3D=original.material
		for slot:String in original.slots:material.set(slot,original.slots[slot])
		material.remove_meta(BINDINGS_META)
	var scene:Node=state.get("scene")
	if is_instance_valid(scene):scene.remove_meta(TABLE_META)
	state.clear();prepared.erase("restore")

static func read_table(descriptor:Dictionary,root:String,trusted_package:bool=true)->Dictionary:
	if descriptor.get("version")!=VERSION or not _sha(descriptor.get("sha256")) or not _integer(descriptor.get("bytes"),MAX_JSON_INTEGER,1) or not _integer(descriptor.get("textures"),MAX_JSON_INTEGER) or not _integer(descriptor.get("image_bytes"),MAX_JSON_INTEGER):return _failed("table_descriptor")
	var path:=table_directory(root).path_join(descriptor.sha256+".json")
	if root.is_empty() or not Paths.allowed(path,root):return _failed("table_path",ERR_FILE_BAD_PATH)
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()!=int(descriptor.bytes):return _failed("table_size")
	var text:=file.get_as_text();file.close()
	if not trusted_package and text.sha256_text()!=descriptor.sha256:return _failed("table_checksum")
	var parsed:Variant=JSON.parse_string(text)
	if not parsed is Dictionary or parsed.get("version")!=VERSION or not parsed.get("textures") is Dictionary or parsed.textures.size()!=int(descriptor.textures):return _failed("table_schema")
	var total:=0;var product_paths:Array=[]
	for id:Variant in parsed.textures:
		var row:Variant=parsed.textures[id]
		if not _sha(id) or not row is Dictionary or row.get("pixel_sha")!=id or row.get("file")!="cache/world3d/model_textures_v1/"+id+".stex":return _failed("texture_identity")
		product_paths.append(root.path_join(row.file))
		if not _integer(row.get("width"),16384,1) or not _integer(row.get("height"),16384,1) or not _integer(row.get("format"),Image.FORMAT_MAX-1) or not _integer(row.get("bytes"),0xffffffff,1) or not _integer(row.get("file_bytes"),MAX_JSON_INTEGER,1):return _failed("texture_layout")
		if not row.get("alpha") is bool or not row.get("normal_xy") is bool or row.normal_xy!=(int(row.format)==Image.FORMAT_RGTC_RG):return _failed("texture_semantics")
		var mips:Variant=row.get("mip_sizes")
		if not mips is Array or mips.is_empty() or mips.size()>17:return _failed("texture_mips")
		var image_bytes:=0
		for amount:Variant in mips:
			if not _integer(amount,0xffffffff,1):return _failed("texture_mip_size")
			image_bytes+=int(amount)
		if image_bytes!=int(row.bytes) or 44+8*mips.size()+image_bytes!=int(row.file_bytes):return _failed("texture_size")
		total+=image_bytes
		for key:String in ["width","height","format","bytes","file_bytes"]:row[key]=int(row[key])
		var integer_mips:Array[int]=[]
		for amount:Variant in mips:integer_mips.append(int(amount))
		row.mip_sizes=integer_mips
	if not _integer(parsed.get("image_bytes"),MAX_JSON_INTEGER) or int(parsed.image_bytes)!=total or int(descriptor.image_bytes)!=total:return _failed("table_image_bytes")
	if not Paths.allowed_many(product_paths,root):return _failed("texture_path",ERR_FILE_BAD_PATH)
	parsed.image_bytes=total
	return {"ok":true,"error":"","table":parsed}
