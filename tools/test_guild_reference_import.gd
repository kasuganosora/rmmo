extends "res://tools/test_world3d_mcp.gd"
## Real AssetLibrary import, source/output/native comparison and isolated HTTP.
## Never writes a formal pack or map. GPU execution belongs to the background wrapper.
## --source-dir=... --out=... [--only=id,id] [--imports-only] [--syntax-only]
## --http-from=<completed import_report.json> reuses exact verified isolated imports.
## --resume-check-only verifies reuse identities headlessly without editor/GPU work.
## --isolated-content scopes import/native/editor together without changing budgets.
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Compile=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Components=preload("res://scripts/world3d/model_components.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
var source_dir:="D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2"
var output_dir:="D:/code/rmmo_runtime/review_artifacts/guild_reference_import_20261013"
var selected:PackedStringArray=[]
var imports_only:=false
var http_from:=""
var resume_check_only:=false
var isolated_content:=false
var previous_content_override:=""
var audit:Dictionary={"checks":[],"items":[],"published":false,"formal_map_modified":false,"visual_acceptance":"separate fixed-camera GPU review required"}
var material_cache:Dictionary={}
var texture_cache:Dictionary={}

func check(ok:bool,label:String)->void:
	print("%s: %s" % ["PASS" if ok else "FAIL",label])
	audit.checks.append({"label":label,"ok":ok})
	if not ok:failed+=1

func stable(value:Variant)->String:return JSON.stringify(value,"",true,true)
func http_runtime_identity()->Dictionary:
	var hashes:Dictionary={}
	for path in ["scripts/world3d/model_components.gd","scripts/world3d/runtime_mesh_cache.gd","scripts/world3d/model_collision_requirements.gd","scripts/world3d/ground_batcher.gd","scripts/world_editor/world_editor.gd","scripts/world_editor/mcp_ops.gd"]:
		hashes[path]=FileAccess.get_sha256("res://"+path)
	return hashes
func digest(bytes:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
func write_json(path:String,value:Variant)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:check(false,"evidence write "+path);return
	file.store_string(JSON.stringify(value,"  ",true,true));file.close()
func flush_report()->void:
	audit.failures=failed;audit.passed=failed==0
	write_json(output_dir+"/import_report.json",audit)

func phase(id:String,name_:String)->int:
	var tick:=Time.get_ticks_msec()
	audit.active={"id":id,"phase":name_,"started_ticks_ms":tick}
	print("GUILD_IMPORT_PHASE ",id," ",name_," ticks_ms=",tick)
	flush_report();return tick

func normalized(value:Variant,depth:int=0)->Variant:
	if depth>24:return {"error":"depth_limit"}
	if value is Texture2D:
		var id:int=value.get_instance_id()
		if texture_cache.has(id):return texture_cache[id]
		var image:Image=value.get_image()
		if image==null or image.is_empty():return {"error":"invalid_texture"}
		image=image.duplicate()
		if image.is_compressed() and image.decompress()!=OK:return {"error":"decompression"}
		var target:int=Image.FORMAT_RGBA8 if image.get_format()<=Image.FORMAT_RGBA8 else Image.FORMAT_RGBAF
		image.convert(target)
		var result:Dictionary={"texture":true,"width":image.get_width(),"height":image.get_height(),"format":target,"mips":image.has_mipmaps(),"pixels_sha":digest(image.get_data())}
		texture_cache[id]=result;return result
	if value is Material:return material_signature(value,depth+1)
	if value is Shader:return {"shader_code":value.code}
	if value is Resource:return {"unsupported_resource":value.get_class()}
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[str(key)]=normalized(value[key],depth+1)
		return result
	if value is Array:
		var result:Array=[]
		for child in value:result.append(normalized(child,depth+1))
		return result
	if value is float or value is int or value is bool or value is String or value==null:return value
	return var_to_str(value)

func material_signature(material:Material,depth:int=0)->Dictionary:
	if material==null:return {"null":true}
	var id:=material.get_instance_id()
	if material_cache.has(id):return material_cache[id]
	var result:Dictionary={"class":material.get_class(),"properties":{}}
	for property:Dictionary in material.get_property_list():
		var key:String=property.name
		if not (int(property.usage)&PROPERTY_USAGE_STORAGE):continue
		if key in ["resource_name","resource_path","resource_scene_unique_id","resource_local_to_scene","script"] or key.begins_with("metadata/"):continue
		result.properties[key]=normalized(material.get(key),depth+1)
	material_cache[id]=result;return result

func semantic_catalog(values:Array)->Array:
	# Native serialization can consolidate byte-identical resource aliases. Each
	# surface's material/texture binding remains checked above; object identity and
	# encounter order are not appearance semantics or evidence of lost texture.
	var unique:Dictionary={}
	for value:Variant in values:unique[stable(value)]=value
	var keys:Array=unique.keys();keys.sort()
	var result:Array=[]
	for key:String in keys:result.append(unique[key])
	return result

func signature(scene:Node)->Dictionary:
	material_cache.clear();texture_cache.clear()
	var nodes:Array[Node]=[scene];nodes.append_array(scene.find_children("*","",true,false))
	var result:Dictionary={"nodes":{},"mesh_nodes":0,"instance_triangles_lod0":0,"hinge_members":0,"light_sockets":0}
	for node:Node in nodes:
		var key:String="." if node==scene else str(scene.get_path_to(node))
		var extra:Dictionary=node.get_meta("extras",{})
		var row:Dictionary={"class":node.get_class(),"extras":normalized(extra)}
		if extra.has("rmmo_hinge"):result.hinge_members+=1
		if extra.has("rmmo_light_socket"):result.light_sockets+=1
		if node is Node3D:row.transform=var_to_str(node.transform);row.visible=node.visible
		if node is MeshInstance3D:
			result.mesh_nodes+=1;row.surfaces=[]
			row.visibility={"begin":node.visibility_range_begin,"end":node.visibility_range_end,"aabb":var_to_str(node.custom_aabb),"cast_shadow":node.cast_shadow}
			if node.mesh!=null:
				for slot in node.mesh.get_surface_count():
					var arrays:Array=node.mesh.surface_get_arrays(slot)
					var count:int=node.mesh.surface_get_array_index_len(slot)
					if count==0:count=node.mesh.surface_get_array_len(slot)
					result.instance_triangles_lod0+=count/3
					var channels:Dictionary={}
					for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_INDEX]:channels[str(channel)]=digest(var_to_bytes(arrays[channel]))
					var stored:Array=node.mesh.get("_surfaces")
					row.surfaces.append({"primitive":node.mesh.surface_get_primitive_type(slot),"vertices":node.mesh.surface_get_array_len(slot),"indices":count,"channels":channels,"lods_sha":digest(var_to_bytes(stored[slot].get("lods",[]))),"blend_sha":digest(var_to_bytes(node.mesh.surface_get_blend_shape_arrays(slot))),"material":material_signature(node.get_active_material(slot))})
		result.nodes[key]=row
	result.textures=semantic_catalog(texture_cache.values());result.materials=semantic_catalog(material_cache.values())
	return result

func differences(a:Variant,b:Variant,path:String="",result:Array=[])->Array:
	if result.size()>=120:return result
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key):result.append({"path":path+"/"+str(key),"kind":"missing_output"})
			else:differences(a[key],b[key],path+"/"+str(key),result)
		for key in b:
			if not a.has(key):result.append({"path":path+"/"+str(key),"kind":"added_output"})
	elif a is Array and b is Array:
		if a.size()!=b.size():result.append({"path":path,"kind":"array_count","input":a.size(),"output":b.size()})
		for index in mini(a.size(),b.size()):differences(a[index],b[index],path+"/"+str(index),result)
	elif not equivalent(a,b):result.append({"path":path,"kind":"changed","input":str(a).left(220),"output":str(b).left(220)})
	return result

func source_signature(path:String)->Dictionary:
	var prepared:Compile.PreparedSource=Compile.prepare_source(path)
	var scene:Node=prepared.get_scene()
	if scene==null:prepared.dispose();return {}
	var result:=signature(scene);scene=null;prepared.dispose();Drainer.synchronize_transfer()
	return result

func import_item(library:RefCounted,id:String,path:String)->Dictionary:
	var row:Dictionary={"id":id,"input_path":path,"input_sha":FileAccess.get_sha256(path),"initial_failures":failed}
	check(FileAccess.file_exists(path),"source exists "+id)
	if not FileAccess.file_exists(path):return row
	phase(id,"input_signature")
	var before:=source_signature(path);check(not before.is_empty(),"input production parse "+id)
	write_json(output_dir+"/"+id+"/input_semantics.json",before)
	var import_started:=phase(id,"AssetLibrary.import_file")
	var imported:Dictionary=library.import_file(path)
	row.import_elapsed_ms=Time.get_ticks_msec()-import_started
	row.import=imported;check(imported.get("ok",false),"real AssetLibrary import "+id)
	if not imported.get("ok",false):return row
	row.entry=imported.entry;row.output_path=imported.entry.asset_path;row.output_sha=FileAccess.get_sha256(row.output_path)
	row.bytes_identical=row.input_sha==row.output_sha
	check(row.output_path.get_file().get_basename()==row.output_sha,"content addressed output SHA "+id)
	phase(id,"output_signature")
	var after:=source_signature(row.output_path);check(not after.is_empty(),"library output production parse "+id)
	write_json(output_dir+"/"+id+"/output_semantics.json",after)
	row.import_differences=differences(before,after,"",[])
	row.semantic_exact=row.import_differences.is_empty()
	# Changes are evidence requiring review, not a blanket claim that a new SHA lost data.
	check(row.semantic_exact,"source to imported geometry/material pixels/extras "+id)
	phase(id,"native_identity_and_reopen")
	var product:Dictionary=Compile.read(row.output_path)
	check(product.get("hit",false),"production native identity hit "+id)
	if product.get("hit",false):
		var packed:PackedScene=product.packed
		var scene:Node=Compile.instantiate(packed)
		check(scene!=null,"closed native reopens "+id)
		if scene!=null:
			var native:=signature(scene)
			row.native_differences=differences(after,native,"",[])
			check(row.native_differences.is_empty(),"imported source to native semantics "+id)
			row.stats={"mesh_nodes":native.mesh_nodes,"instance_triangles_lod0":native.instance_triangles_lod0,"hinge_members":native.hinge_members,"light_sockets":native.light_sockets}
			scene.free()
		row.native_manifest=JSON.parse_string(FileAccess.get_file_as_string(Compile.index_path(row.output_path)))
		# Measure the exact production-validated native. Gallery PackedScenes do
		# not carry this validation stamp, so their empty Footprint.measure output
		# is not a resource cost result.
		phase(id,"validated_native_resource_cost")
		var native_path:=Compile.directory().path_join(str(row.native_manifest.payload_sha)+".scn")
		row.native_resource_stats=Footprint.measure(packed)
		check(not row.native_resource_stats.is_empty(),"validated native resource graph measured "+id)
		row.native_resource_stats.native_uncompressed_bytes=Footprint.native_uncompressed_bytes(native_path)
		row.conservative_admission=Footprint.estimate_stats(row.native_resource_stats)
		check(not row.conservative_admission.is_empty(),"bounded native admission estimate "+id)
		row.resource_cost_note="Native graph/decoded costs and conservative admission only; not measured per-model RSS or VRAM."
		packed=null;product.clear();Drainer.synchronize_transfer()
	else:Drainer.dispose_result(product)
	check(FileAccess.get_sha256(path)==row.input_sha,"author source unchanged "+id)
	row.passed=failed==row.initial_failures
	audit.erase("active")
	write_json(output_dir+"/"+id+"/import.json",row)
	return row

func wait_loaded(id:String="")->void:
	for frame in 12000:
		await process_frame
		if frame>45 and not editor.saving() and editor._view!=null and (id.is_empty() or editor._view.get_node_or_null(id)!=null):return
	check(false,"editor readiness timeout "+id)

func reused_items(requested:Array)->Array:
	var result:Array=[]
	var original:Variant=JSON.parse_string(FileAccess.get_file_as_string(http_from))
	check(original is Dictionary and original.get("completed",false),"completed prior import report")
	if not original is Dictionary or not original.get("completed",false):return result
	check(original.get("generator")==Compile.generator(),"reused import generator unchanged")
	var catalog_root:String=str(original.get("isolation_root",""))
	check(catalog_root.begins_with(Paths.cache_directory("guild_reference_import_")),"prior catalog remains isolated cache")
	if failed>0:return result
	var library:=Library.new(catalog_root+"/assets")
	audit.reused_import_evidence={"path":http_from,"sha256":FileAccess.get_sha256(http_from),"isolation_root":catalog_root,"prior_http_failures":original.get("failures"),"reason":"Repeat HTTP after isolated catalog fixture correction; no source/native evidence reused across changed identities."}
	for item:Dictionary in requested:
		var matches:Array=original.get("items",[]).filter(func(r):return r.get("id")==item.id)
		check(matches.size()==1,"unique prior import evidence "+item.id)
		if matches.size()!=1:continue
		var row:Dictionary=matches[0].duplicate(true)
		var before_failures:=failed
		check(row.get("passed",false) and row.get("semantic_exact",false) and row.get("native_differences",["missing"]).is_empty(),"prior source/output/native semantics passed "+item.id)
		check(str(row.get("input_path","")).simplify_path()==str(item.path).simplify_path() and FileAccess.get_sha256(item.path)==row.get("input_sha"),"reused author source identity "+item.id)
		check(str(row.get("output_path","")).get_base_dir()==catalog_root+"/assets" and FileAccess.get_sha256(row.get("output_path",""))==row.get("output_sha"),"reused actual catalog GLB identity "+item.id)
		var entries:Array=library.entries.filter(func(e):return e.get("asset_path")==row.get("output_path") and e.get("label")==row.get("entry",{}).get("label"))
		check(entries.size()==1,"reused persisted catalog entry "+item.id)
		var current:Variant=JSON.parse_string(FileAccess.get_file_as_string(Compile.index_path(row.get("output_path",""))))
		check(current is Dictionary and equivalent(current,row.get("native_manifest",{})),"reused native manifest exact "+item.id)
		if current is Dictionary:
			var product_path:=Compile.directory().path_join(str(current.get("payload_sha",""))+".scn")
			check(current.get("generator")==Compile.generator() and current.get("source_sha")==row.get("output_sha") and FileAccess.get_sha256(product_path)==current.get("payload_sha"),"reused native payload identity "+item.id)
		check(not row.get("native_resource_stats",{}).is_empty() and not row.get("conservative_admission",{}).is_empty(),"reused measured native costs "+item.id)
		if failed!=before_failures:continue
		row.erase("http_passed");row.reused_import_report=http_from
		result.append(row)
	return result

func http_item(row:Dictionary,map_path:String)->void:
	var before_failures:=failed
	var listing:=await call_tool("list_assets",{"query":row.entry.label})
	var matches:Array=listing.get("assets",[]).filter(func(r):return r.get("name","")==row.entry.label)
	check(matches.size()==1,"unique real catalog identity "+row.id)
	if matches.size()!=1:return
	var snapshot:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("place_asset",{"asset_id":"invalid_guild_reference","position":[0,0,0]},false)
	check(equivalent(snapshot,editor._doc.recovery_snapshot()),"invalid placement atomic "+row.id)
	await call_tool("place_asset",{"asset_id":matches[0].asset_id,"position":[0,0,0]})
	check(editor._doc.records.size()==1,"single isolated asset "+row.id)
	if editor._doc.records.is_empty():return
	var id:String=editor._doc.records[0].uuid
	await wait_loaded(id)
	await call_tool("select_objects",{"ids":[id]})
	check(editor._view.get_node_or_null(id)!=null,"selectable native instance "+row.id)
	row.editor_collision_bodies=editor._bodies_by_uuid.get(id,[]).size()
	row.batch_groups=editor._ground_batches.groups.size() if editor._ground_batches!=null else 0
	await call_tool("undo");await wait_loaded();check(editor._doc.records.is_empty(),"placement undo "+row.id)
	await call_tool("redo");await wait_loaded(id);check(editor._doc.records.size()==1,"placement redo "+row.id)
	var component:=""
	var listed:=await call_tool("list_building_components",{"id":id})
	if listed.get("ok",false):
		row.component_count=listed.get("components",[]).size()
		for member:Dictionary in listed.get("components",[]):
			if not str(member.id).contains("architecture:"):component=member.id;break
	if not component.is_empty():
		await call_tool("select_objects",{"ids":[id]})
		var history:int=editor._doc._undo.size()
		await call_tool("set_building_component_state",{"id":id,"component_id":component,"open":.5})
		check(editor._doc._undo.size()==history+1,"component one undo "+row.id)
		for body:StaticBody3D in editor._bodies_by_uuid.get(id,[]):check(body.global_transform.is_equal_approx(body.get_meta("visual").global_transform),"moving collision follows "+row.id)
		var saved:Dictionary=editor._doc.recovery_snapshot()
		await call_tool("set_building_component_state",{"id":id,"component_id":component,"open":2.0},false)
		check(equivalent(saved,editor._doc.recovery_snapshot()),"bad component value atomic "+row.id)
		await call_tool("undo");await call_tool("redo")
	await call_tool("save_world")
	await call_tool("open_world",{"path":map_path});await wait_loaded(id)
	# Opening refreshes asset scope; restore only this isolated catalog for the next case.
	check(editor._doc.records.size()==1 and editor._doc.missing_assets().is_empty(),"actual save/open dependencies "+row.id)
	if not component.is_empty():check(editor._doc._find(id).get("model_component_states",{}).get(component)==.5,"saved hinge value reopens "+row.id)
	var reopened=Doc.open_file(map_path);check(reopened!=null and reopened.records.size()==1,"document native reopen "+row.id)
	await call_tool("select_objects",{"ids":[id]});await call_tool("delete_selection");await wait_loaded()
	check(editor._doc.records.is_empty(),"delete isolated instance "+row.id)
	row.http_passed=failed==before_failures

func run()->void:
	var args:=OS.get_cmdline_user_args()
	for i in args.size():
		var arg:String=args[i]
		if arg=="--syntax-only":print("GUILD_REFERENCE_IMPORT syntax only");quit();return
		if arg.begins_with("--source-dir="):source_dir=arg.trim_prefix("--source-dir=")
		if arg=="--source-dir" and i+1<args.size():source_dir=args[i+1]
		if arg.begins_with("--out="):output_dir=arg.trim_prefix("--out=")
		if arg=="--out" and i+1<args.size():output_dir=args[i+1]
		if arg.begins_with("--only="):selected=arg.trim_prefix("--only=").split(",",false)
		if arg=="--imports-only":imports_only=true
		if arg.begins_with("--http-from="):http_from=arg.trim_prefix("--http-from=")
		if arg=="--resume-check-only":resume_check_only=true
		if arg=="--isolated-content":isolated_content=true
	output_dir=output_dir.replace("\\","/").simplify_path().trim_suffix("/")
	if not output_dir.begins_with("D:/code/rmmo_runtime/review_artifacts/") and not output_dir.begins_with("D:/code/rmmo/review_artifacts/"):
		push_error("Output must remain in an isolated review_artifacts directory");quit(2);return
	if DisplayServer.get_name()=="headless" and not resume_check_only:push_error("Use run_godot_background.py; headless only supports --syntax-only or --resume-check-only");quit(2);return
	if resume_check_only and http_from.is_empty():push_error("--resume-check-only requires --http-from");quit(2);return
	Engine.max_fps=60;rpc_timeout_ms=120000;root.size=Vector2i(1100,800)
	create_timer(3600).timeout.connect(func():audit.timeout=true;flush_report();push_error("Guild import audit timeout");quit(2))
	if isolated_content:
		var shared_root:=Paths.external_root()
		var content_root:=Paths.cache_directory("guild_reference_native_scope_%d"%Time.get_ticks_usec())
		if not http_from.is_empty():
			var prior:Variant=JSON.parse_string(FileAccess.get_file_as_string(http_from))
			var recorded_root:String=str(prior.get("content_root","")) if prior is Dictionary else ""
			check(not recorded_root.is_empty() and Paths.allowed(recorded_root,shared_root) and recorded_root.get_file().begins_with("guild_reference_native_scope_"),"reused import has confined isolated content root")
			if failed>0:flush_report();quit(1);return
			content_root=recorded_root
		check(DirAccess.make_dir_recursive_absolute(content_root)==OK,"create isolated native content root")
		var manager:=root.get_node("AssetManager")
		previous_content_override=manager.content_root_override;manager.content_root_override=content_root
		check(Paths.external_root()==content_root and Compile.directory().begins_with(content_root+"/"),"production import/native/editor share isolated root")
		audit.content_root=content_root;audit.shared_content_root=shared_root;audit.native_cache_directory=Compile.directory();audit.native_cache_limit_bytes=Compile.MAX_CACHE_BYTES
		audit.isolation_note="Existing process-only content_root_override; no production budget increase, shared cache eviction or persistent settings write."
	var directory:=Paths.cache_directory("guild_reference_import_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var library:=Library.new(directory+"/assets")
	audit.merge({"source_dir":source_dir,"isolation_root":directory,"generator":Compile.generator(),"engine":Engine.get_version_info(),"real_http":not imports_only})
	var requested:Array=[{"id":"axel_guild_repaired","path":source_dir+"/axel_guild_repaired.glb"},{"id":"guild_alarm_tower","path":source_dir+"/guild_alarm_tower.glb"}]
	var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string(source_dir+"/repair_manifest.json"))
	if not manifest is Dictionary or not manifest.get("library") is Array:check(false,"valid source manifest");flush_report();quit(1);return
	for row:Dictionary in manifest.library:requested.append({"id":row.asset_id,"path":source_dir+"/library/"+str(row.asset_id)+".glb"})
	if not selected.is_empty():requested=requested.filter(func(r):return str(r.id) in selected)
	check(not requested.is_empty(),"nonempty selected assets")
	if not http_from.is_empty():
		audit.items=reused_items(requested)
		check(audit.items.size()==requested.size(),"all requested imports have exact reusable proof")
		if failed>0:flush_report();quit(1);return
		library=Library.new(str(audit.reused_import_evidence.isolation_root)+"/assets")
		audit.isolation_root=audit.reused_import_evidence.isolation_root
	else:
		for item:Dictionary in requested:
			var row:=import_item(library,item.id,item.path)
			audit.items.append(row);flush_report();await process_frame
	if resume_check_only:
		audit.real_http=false;audit.identity_check_only=true;audit.completed=true;flush_report()
		print("GUILD_REFERENCE_IMPORT resume identities verified; HTTP not run");quit(0);return
	if not imports_only:
		audit.http_runtime_identity=http_runtime_identity()
		var map_path:=directory+"/map.gltf";var doc:=Doc.new();check(doc.save(map_path)==OK,"isolated empty map")
		var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=map_path;session.world3d_editor_doc=null
		editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory+"/drafts";root.add_child(editor);await wait_loaded();editor._safety.enabled=false
		var probe:=TCPServer.new();port=29840
		while probe.listen(port,"127.0.0.1")!=OK:port+=1
		probe.stop();check(editor.start_mcp(port).ok,"isolated 3D HTTP start")
		await rpc("initialize",{"protocolVersion":"2025-03-26"})
		var names:Array=(await rpc("tools/list")).get("result",{}).get("tools",[]).map(func(t):return t.name)
		check(names.has("place_asset") and names.has("set_building_component_state"),"current 3D tool discovery")
		for row:Dictionary in audit.items:
			if not row.has("entry"):continue
			# open_world outside a registered pack clears _assets.entries in-place.
			# Reconstruct from persisted isolated catalog instead of reusing that
			# mutated RefCounted object. Never register a test pack in user settings.
			editor._assets=Library.new(library.directory);editor._shared_assets=[]
			await http_item(row,map_path);flush_report()
		audit.isolated_map=map_path
		check(equivalent(audit.http_runtime_identity,http_runtime_identity()),"HTTP runtime implementation unchanged during batch")
		editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_doc=null;session.world3d_editor_path=""
	if isolated_content:root.get_node("AssetManager").content_root_override=previous_content_override
	audit.completed=true;flush_report()
	print("GUILD_REFERENCE_IMPORT complete failures=",failed," report=",output_dir+"/import_report.json")
	quit(0 if failed==0 else 1)
