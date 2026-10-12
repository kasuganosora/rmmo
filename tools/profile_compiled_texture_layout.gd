extends SceneTree
## Isolated RGB8/RGBA8 native-product experiment. Run on the private GPU desktop.
## Never rebuilds production products or invokes the global grass texture pool.
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Grass=preload("res://scripts/world3d/grass_texture_cache.gd")
const FLAGS=ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS
const RECIPE="private_rgb8_to_rgba8_all_mips_v1"
var asset:=""
var output:=""
var phase:="load"
var candidate:=""
var report:Dictionary={"failures":0,"checks":[],"timings_us":{},"scope":"Isolated native product; no gameplay, SceneTree scene attachment, grass sharing or first-frame measurement."}
var clones:Dictionary={}
var watched:Dictionary={}
var held:Array=[]
var scenes:Array[Node]=[]
var converted:Array=[]
var output_allowed:=false

func _initialize()->void:run.call_deferred()

func check(ok:bool,label_:String)->bool:
	report.checks.append({"ok":ok,"label":label_})
	print("PASS " if ok else "FAIL ",label_)
	if not ok:report.failures+=1
	return ok

func sha_bytes(bytes:PackedByteArray)->String:
	var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(bytes)
	return hash_.finish().hex_encode()

func read_json(path:String)->Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>1024*1024:return {}
	var value:Variant=JSON.parse_string(file.get_as_text());file.close()
	return value if value is Dictionary else {}

func file_size(path:String)->int:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return -1
	var size:=file.get_length();file.close();return size

func watch(value:Resource)->void:
	if value!=null:watched[value.get_instance_id()]={"ref":weakref(value),"class":value.get_class()}

func image_description(image:Image)->Dictionary:
	var data:=image.get_data();var mips:Array=[]
	for mip in range(image.get_mipmap_count()+1):
		var begin:int=image.get_mipmap_offset(mip)
		var end:int=image.get_mipmap_offset(mip+1) if mip<image.get_mipmap_count() else data.size()
		mips.append({"level":mip,"bytes":end-begin,"sha256":sha_bytes(data.slice(begin,end))})
	return {"width":image.get_width(),"height":image.get_height(),"format":image.get_format(),"mipmaps":image.has_mipmaps(),"mipmap_count":image.get_mipmap_count(),"logical_bytes":data.size(),"mips":mips}

func copy_texture(texture:ImageTexture)->ImageTexture:
	var source_image:=texture.get_image()
	if source_image==null:check(false,"texture provides readable image");return texture
	if texture.get_format()!=Image.FORMAT_RGB8:return texture
	if not check(texture.get_width()==source_image.get_width() and texture.get_height()==source_image.get_height(),"RGB8 candidate rejects texture size overrides"):return texture
	if not check(source_image.get_format()==Image.FORMAT_RGB8,"RGB8 texture readback preserves its declared source format"):return texture
	var before:=image_description(source_image)
	var rgba:Image=source_image.duplicate();rgba.convert(Image.FORMAT_RGBA8)
	var roundtrip:Image=rgba.duplicate();roundtrip.convert(Image.FORMAT_RGB8)
	var restored:=image_description(roundtrip)
	if not check(before==restored,"RGB8→RGBA8→RGB8 retains dimensions and every existing mip byte"):return texture
	var replacement:=ImageTexture.create_from_image(rgba)
	clones[texture.get_instance_id()]=replacement
	replacement.resource_name=texture.resource_name;replacement.resource_local_to_scene=texture.resource_local_to_scene
	for name_:StringName in texture.get_meta_list():
		if name_!=&"compiled_grass_pixel_key":replacement.set_meta(name_,copy_value(texture.get_meta(name_),1))
	converted.append({"texture_source_id":texture.get_instance_id(),"before":before,"after":image_description(rgba),"roundtrip_equal":true,"old_grass_pixel_key_removed":not replacement.has_meta("compiled_grass_pixel_key")})
	watch(replacement)
	return replacement

func copy_value(value:Variant,depth:int=0)->Variant:
	if depth>40:check(false,"private copy graph stays within depth limit");return value
	if value is Resource:
		watch(value)
		var id:int=value.get_instance_id()
		if clones.has(id):return clones[id]
		if value is ImageTexture:
			var texture:ImageTexture=copy_texture(value);clones[id]=texture;return texture
		if value is Image:
			var image:Image=value.duplicate();clones[id]=image;watch(image);return image
		if not value is ArrayMesh and not value is StandardMaterial3D:
			check(false,"copy rejects unexpected resource class "+value.get_class());return value
		var copied:Resource=value.duplicate(false);clones[id]=copied;watch(copied)
		if value is ArrayMesh:
			# duplicate(false) preserves the complete geometry/LOD/blend-shape
			# storage. Replace only material references, never reconstruct arrays.
			for surface in value.get_surface_count():(copied as ArrayMesh).surface_set_material(surface,copy_value(value.surface_get_material(surface),depth+1))
			if value.shadow_mesh!=null:(copied as ArrayMesh).shadow_mesh=copy_value(value.shadow_mesh,depth+1)
		else:
			for info:Dictionary in value.get_property_list():
				if not int(info.usage)&PROPERTY_USAGE_STORAGE or str(info.name).begins_with("resource_") or info.name==&"script":continue
				var before:Variant=value.get(info.name);var after:Variant=copy_value(before,depth+1)
				if after!=before:copied.set(info.name,after)
		for name_:StringName in value.get_meta_list():copied.set_meta(name_,copy_value(value.get_meta(name_),depth+1))
		return copied
	if value is Dictionary:
		var result:Dictionary={}
		for key:Variant in value:result[key]=copy_value(value[key],depth+1)
		return result
	if value is Array:
		var result:Array=value.duplicate()
		for i in value.size():result[i]=copy_value(value[i],depth+1)
		return result
	return value

func patch_nodes(node:Node)->void:
	for info:Dictionary in node.get_property_list():
		if not int(info.usage)&PROPERTY_USAGE_STORAGE or info.name in [&"script",&"owner"]:continue
		var before:Variant=node.get(info.name);var after:Variant=copy_value(before)
		if after!=before:node.set(info.name,after)
	for child:Node in node.get_children():patch_nodes(child)

func metadata_signature(value:Object,seen:Dictionary)->Dictionary:
	var result:Dictionary={};var names:Array=value.get_meta_list();names.sort()
	for name_:StringName in names:
		if name_==&"compiled_grass_pixel_key":continue
		result[str(name_)]=value_signature(value.get_meta(name_),seen)
	return result

func ordered_properties(value:Object)->Array[Dictionary]:
	var properties:Array[Dictionary]=value.get_property_list()
	properties.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return str(a.name)<str(b.name))
	return properties

func value_signature(value:Variant,seen:Dictionary,depth:int=0)->Variant:
	if depth>48:check(false,"verification graph stays within depth limit");return "depth_error"
	if value is Resource:
		watch(value)
		var id:int=value.get_instance_id()
		if seen.has(id):return {"alias":seen[id]}
		var slot:=seen.size();seen[id]=slot
		var result:Dictionary={"id":slot,"class":value.get_class(),"name":value.resource_name,"local_to_scene":value.resource_local_to_scene,"metadata":metadata_signature(value,seen)}
		if value is ImageTexture or value is Image:
			if value is ImageTexture:result.texture_dimensions=[value.get_width(),value.get_height()]
			var image:Image=value.get_image() if value is ImageTexture else value
			if image==null:check(false,"verification obtains texture pixels");return result
			# RGB8 and its exact opaque RGBA8 representation share the canonical
			# bytes; other formats keep their full original precision.
			var canonical:Image=image.duplicate()
			if canonical.get_format()==Image.FORMAT_RGB8:canonical.convert(Image.FORMAT_RGBA8)
			result.image=image_description(canonical)
			return result
		var properties:Dictionary={}
		for info:Dictionary in ordered_properties(value):
			if not int(info.usage)&PROPERTY_USAGE_STORAGE or str(info.name).begins_with("metadata/") or info.name in [&"resource_path",&"resource_name",&"resource_local_to_scene",&"resource_scene_unique_id",&"script"]:continue
			properties[str(info.name)]=value_signature(value.get(info.name),seen,depth+1)
		result.properties=properties
		return result
	if value is Dictionary:
		var result:Array=[];var keys:Array=value.keys();keys.sort_custom(func(a,b):return var_to_bytes(a).hex_encode()<var_to_bytes(b).hex_encode())
		for key:Variant in keys:result.append([var_to_bytes(key).hex_encode(),value_signature(value[key],seen,depth+1)])
		return {"dictionary_entries":result}
	if value is Array:
		var result:Array=[]
		for child:Variant in value:result.append(value_signature(child,seen,depth+1))
		return result
	if typeof(value)>=TYPE_PACKED_BYTE_ARRAY:return {"packed_type":typeof(value),"count":value.size(),"sha256":sha_bytes(var_to_bytes(value))}
	return value

func scene_signature(node:Node,seen:Dictionary)->Dictionary:
	var properties:Dictionary={}
	for info:Dictionary in ordered_properties(node):
		if not int(info.usage)&PROPERTY_USAGE_STORAGE or str(info.name).begins_with("metadata/") or info.name in [&"script",&"owner"]:continue
		properties[str(info.name)]=value_signature(node.get(info.name),seen)
	var children:Array=[]
	for child:Node in node.get_children():children.append(scene_signature(child,seen))
	return {"class":node.get_class(),"name":str(node.name),"properties":properties,"metadata":metadata_signature(node,seen),"groups":node.get_groups(),"children":children}

func texture_inventory(packed:PackedScene)->Dictionary:
	var pending:Array=[];var seen:Dictionary={};var textures:Array=[];var formats:Dictionary={};var bytes:=0
	var state:=packed.get_state()
	for node in state.get_node_count():
		for property in state.get_node_property_count(node):pending.append(state.get_node_property_value(node,property))
	while not pending.is_empty():
		var value:Variant=pending.pop_back()
		if value is Resource:
			var id:int=value.get_instance_id()
			if seen.has(id):continue
			seen[id]=true;watch(value)
			if value is ImageTexture:
				var image:Image=value.get_image()
				if image==null:check(false,"inventory reads texture image");continue
				var row:=image_description(image);row.texture_format=value.get_format();row.name=value.resource_name
				textures.append(row);bytes+=int(row.logical_bytes)
				var format:String=str(row.texture_format);formats[format]=int(formats.get(format,0))+1
			elif value is Image:continue
			else:
				for info:Dictionary in value.get_property_list():
					if int(info.usage)&PROPERTY_USAGE_STORAGE:pending.append(value.get(info.name))
		elif value is Dictionary:pending.append_array(value.values())
		elif value is Array:pending.append_array(value)
	return {"unique_image_textures":textures.size(),"formats":formats,"logical_pixel_bytes":bytes,"textures":textures,"resource_count":seen.size(),"format_rgb8":Image.FORMAT_RGB8,"format_rgba8":Image.FORMAT_RGBA8,"note":"Readback/inventory happens outside the timed load/sync window; logical image bytes are not driver allocation."}

func source_manifest(root_path:String)->Dictionary:
	var path:=Compiled.index_path(asset,root_path);var index:=read_json(path)
	if not check(index.get("version")==Compiled.VERSION and index.get("generator")==Compiled.generator() and Compiled._sha(index.get("source_sha")) and Compiled._sha(index.get("payload_sha")),"existing production manifest matches this engine/generator"):return {}
	var product:String=Compiled.directory(root_path).path_join(str(index.payload_sha)+".scn")
	if not check(Paths.allowed(product,Compiled.directory(root_path)) and file_size(product)==int(index.get("bytes",-1)),"original product exists with exact recorded length"):return {}
	index.product=product;return index

func build_candidate(root_path:String,index:Dictionary)->void:
	var started:=Time.get_ticks_usec();var loaded:=Compiled.read(asset,str(index.source_sha),root_path)
	report.timings_us.verified_compiled_read=Time.get_ticks_usec()-started
	if not check(loaded.get("hit",false),"build reads a currently verified private production PackedScene"):return
	var packed:PackedScene=loaded.packed;held.append(packed);watch(packed)
	var current:Dictionary=read_json(Compiled.index_path(asset,root_path))
	if not check(current.get("source_sha")==index.source_sha and current.get("payload_sha")==index.payload_sha and current.get("generator")==index.generator,"build keeps the same production manifest generation"):return
	report.original_inventory=texture_inventory(packed)
	var original:=packed.instantiate();scenes.append(original)
	var before:Dictionary=scene_signature(original,{})
	var copy:=original.duplicate(Node.DUPLICATE_GROUPS);scenes.append(copy)
	patch_nodes(copy)
	if not check(report.failures==0 and not converted.is_empty(),"private scene has at least one losslessly converted RGB8 texture"):return
	var after:Dictionary=scene_signature(copy,{})
	if not check(before==after,"copied geometry, materials, colors, aliases, metadata and all mip pixels match source"):return
	check(before==scene_signature(original,{}),"private source resources remain unchanged after candidate conversion")
	Compiled._own(copy,copy)
	var product:=PackedScene.new();held.append(product);watch(product)
	if not check(product.pack(copy)==OK and Compiled._valid_packed(product),"candidate packs as the same supported static resource graph"):return
	report.candidate_inventory=texture_inventory(product);report.converted=converted
	started=Time.get_ticks_usec();var error:=ResourceSaver.save(product,candidate,FLAGS)
	report.timings_us.save_candidate=Time.get_ticks_usec()-started
	if not check(error==OK and ResourceLoader.get_dependencies(candidate).is_empty(),"candidate saves bundled/compressed without external dependencies"):return
	if not check(FileAccess.get_sha256(asset)==index.source_sha and FileAccess.get_sha256(index.product)==index.payload_sha,"source GLB and production native product stay unchanged"):return
	var descriptor:Dictionary={"version":1,"recipe":RECIPE,"source_path":asset,"source_sha":index.source_sha,"original_payload_sha":index.payload_sha,"generator":index.generator,"candidate_sha":FileAccess.get_sha256(candidate),"candidate_bytes":file_size(candidate),"flags":FLAGS,"canonical_scene_sha":sha_bytes(var_to_bytes(before)),"converted_textures":converted.size(),"inventory":report.candidate_inventory}
	var file:=FileAccess.open(candidate+".layout.json",FileAccess.WRITE)
	if not check(file!=null,"open candidate identity sidecar"):return
	file.store_string(JSON.stringify(descriptor,"\t"));file.close();report.candidate_descriptor=descriptor

func load_worker(product:String,payload_sha:String,source_sha:String)->Dictionary:
	var times:Dictionary={};var started:=Time.get_ticks_usec()
	var digest:=FileAccess.get_sha256(asset);times.source_sha=Time.get_ticks_usec()-started
	if digest!=source_sha:return {"error":"source_sha","times":times}
	started=Time.get_ticks_usec();digest=FileAccess.get_sha256(product);times.payload_sha=Time.get_ticks_usec()-started
	if digest!=payload_sha:return {"error":"payload_sha","times":times}
	started=Time.get_ticks_usec();var dependencies:=ResourceLoader.get_dependencies(product);times.dependencies=Time.get_ticks_usec()-started
	if not dependencies.is_empty():return {"error":"external_dependencies","times":times}
	started=Time.get_ticks_usec();var packed:=ResourceLoader.load(product,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	times.native_load=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec();var valid:bool=packed!=null and Compiled._valid_packed(packed);times.validate=Time.get_ticks_usec()-started
	# Main thread retains any partially accepted resource until renderer sync.
	return {"error":"" if valid else "invalid_product","packed":packed,"times":times}

func load_product(index:Dictionary)->void:
	var product:String=index.product;var expected:String=index.payload_sha;var descriptor:Dictionary={}
	if not candidate.is_empty():
		descriptor=read_json(candidate+".layout.json")
		if not check(descriptor.get("version")==1 and descriptor.get("recipe")==RECIPE and descriptor.get("source_path")==asset and descriptor.get("source_sha")==index.source_sha and descriptor.get("original_payload_sha")==index.payload_sha and descriptor.get("generator")==index.generator and Compiled._sha(descriptor.get("candidate_sha")) and file_size(candidate)==int(descriptor.get("candidate_bytes",-1)),"candidate sidecar binds this source and original native generation"):return
		product=candidate;expected=descriptor.candidate_sha
	report.product=product;report.product_bytes=file_size(product);report.arm="original" if candidate.is_empty() else "rgba8_candidate"
	var began:=Time.get_ticks_usec();var worker:=Thread.new()
	if not check(worker.start(load_worker.bind(product,expected,index.source_sha))==OK,"start isolated native-load worker"):return
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish();worker=null
	report.timings_us.merge(result.times);report.timings_us.worker_wall=Time.get_ticks_usec()-began
	var packed:PackedScene=result.get("packed")
	if packed!=null:held.append(packed);watch(packed)
	if not check(str(result.get("error","")).is_empty() and packed!=null,"native load passes full source/payload SHA and resource validation"):return
	began=Time.get_ticks_usec();var scene:=packed.instantiate();scenes.append(scene)
	report.timings_us.instantiate=Time.get_ticks_usec()-began
	began=Time.get_ticks_usec();RenderingServer.force_sync();report.timings_us.force_sync=Time.get_ticks_usec()-began
	report.timings_us.load_through_sync=report.timings_us.native_load+report.timings_us.validate+report.timings_us.instantiate+report.timings_us.force_sync
	report.timing_note="native_load and validate run on one private worker; instantiate and force_sync run on main. Worker SHA precedes native load. load_through_sync is the sum of these sequential stages, excludes scheduling gaps/source SHA/inventory, and is not a gameplay first-frame metric."
	# Pixel readback and recursive hashes are verification, not native-load time.
	began=Time.get_ticks_usec();report.inventory=texture_inventory(packed)
	var canonical_sha:=sha_bytes(var_to_bytes(scene_signature(scene,{})))
	report.canonical_scene_sha=canonical_sha;report.timings_us.inventory_and_semantic_hash=Time.get_ticks_usec()-began
	if not descriptor.is_empty():check(canonical_sha==descriptor.canonical_scene_sha,"reloaded candidate retains the source semantic/pixel/alias fingerprint")
	began=Time.get_ticks_usec();check(FileAccess.get_sha256(asset)==index.source_sha,"source remains unchanged through native preparation");report.timings_us.final_source_sha=Time.get_ticks_usec()-began

func cleanup()->void:
	RenderingServer.force_sync()
	for scene:Node in scenes:
		if is_instance_valid(scene):scene.free()
	scenes.clear()
	# Keep resource owners until all instance destruction commands are synced.
	RenderingServer.force_sync();clones.clear();held.clear()
	await process_frame;RenderingServer.force_sync();await process_frame
	var alive:Array=[]
	for id:int in watched:
		if watched[id].ref.get_ref()!=null:alive.append({"id":id,"class":watched[id].class})
	report.retained_resources=alive;check(alive.is_empty(),"all private scene resources release after renderer synchronization")

func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--asset="):asset=argument.trim_prefix("--asset=").replace("\\","/").simplify_path()
		elif argument.begins_with("--output="):output=argument.trim_prefix("--output=").replace("\\","/").simplify_path()
		elif argument.begins_with("--phase="):phase=argument.trim_prefix("--phase=")
		elif argument.begins_with("--candidate="):candidate=argument.trim_prefix("--candidate=").replace("\\","/").simplify_path()
	var root_path:=Paths.external_root();var reviews:=root_path.path_join("review_artifacts")
	output_allowed=output.is_absolute_path() and output.get_extension()=="json" and Paths.allowed(output,reviews)
	if not check(output_allowed,"output is an explicit external review JSON"):quit(1);return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	report.asset=asset;report.phase=phase;report.engine=Engine.get_version_info();report.executable=OS.get_executable_path();report.renderer=ProjectSettings.get_setting("rendering/renderer/rendering_method","");report.save_flags=FLAGS
	var features:Dictionary={}
	for feature:String in ["editor","debug","release","template","template_debug","template_release"]:features[feature]=OS.has_feature(feature)
	report.features=features
	var args_valid:bool=check(DisplayServer.get_name()!="headless","experiment requires real GPU and the private-desktop runner") and check(asset.is_absolute_path() and asset.get_extension().to_lower()=="glb" and Paths.allowed(asset,root_path) and FileAccess.file_exists(asset),"source is an allowed existing absolute GLB") and check(phase in ["build","load"],"phase is build or load")
	if not candidate.is_empty():args_valid=check(candidate.is_absolute_path() and candidate.get_extension()=="scn" and Paths.allowed(candidate,reviews) and candidate!=asset,"candidate stays in external review artifacts") and args_valid
	if phase=="build":args_valid=check(not candidate.is_empty() and not FileAccess.file_exists(candidate) and not FileAccess.file_exists(candidate+".layout.json"),"build requires a new explicit candidate path") and args_valid
	var original_grass:Dictionary=Grass._textures.duplicate()
	if args_valid:
		if phase=="build":DirAccess.make_dir_recursive_absolute(candidate.get_base_dir())
		var index:=source_manifest(root_path)
		if not index.is_empty():
			report.source_sha=index.source_sha;report.original_payload_sha=index.payload_sha
			if phase=="build":build_candidate(root_path,index)
			else:await load_product(index)
		await cleanup()
	check(Grass._textures==original_grass,"experiment never modifies the global grass-sharing cache")
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("COMPILED_TEXTURE_LAYOUT_FINISHED failures=",report.failures," output=",output)
	quit(1 if report.failures else 0)
