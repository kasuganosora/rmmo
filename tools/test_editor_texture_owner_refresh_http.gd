extends "res://tools/test_world3d_mcp.gd"
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
class RefreshJob extends "res://scripts/world_editor/load_job.gd":
	var target:String
	var interrupted:=false
	var refresh_at_slot:=false
	var attempts:=0
	var changed_source:String
	var publish_on_refresh:=false
	var import_owner:Texture2D
	func _prepare_record_textures(record:Dictionary)->Dictionary:
		var packet:Dictionary=await super._prepare_record_textures(record)
		if str(record.get("uuid",""))==target:
			attempts+=1
			if not interrupted and not packet.get("owners",{}).is_empty():refresh_at_slot=true
		return packet
	func _publication_slot()->bool:
		if refresh_at_slot:
			refresh_at_slot=false;interrupted=true
			await get_tree().process_frame
			var replacement:=Image.create(32,32,false,Image.FORMAT_RGBA8);replacement.fill(Color.BLUE)
			replacement.save_png(changed_source)
			Paint.refresh_texture_source(changed_source)
			if publish_on_refresh:
				# Emulate an already running import's real main-thread publication.
				# Keep its returned allocation owned while returning the hot cache
				# to zero, so the next record must use the weak-owner path.
				replacement.generate_mipmaps();replacement.set_meta("runtime_source_sha256",FileAccess.get_sha256(changed_source));replacement.set_meta("runtime_texture_representation","source")
				var saved_budget:=Paint.cache_byte_budget;Paint.cache_byte_budget=16384
				Paint.publish_import_texture(changed_source,replacement)
				import_owner=Paint.retained_texture(Paint.texture_key(changed_source))
				Paint.cache_byte_budget=saved_budget;Paint.trim_cached_resources()
		return await super._publication_slot()

func make_record(doc:RefCounted,kind:String,index:int,definition:Dictionary)->String:
	var id:String=doc.add_box("grass",Vector3(index*12,0,0),Vector3(8,1,8))
	var record:Dictionary=doc._find(id)
	record.collision="block"
	if kind=="terrain":
		record.terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-8.,"heights":[0.,0.,0.,0.,0.,0.,0.,0.,0.],"holes":[false,false,false,false]}
		record.terrain_material=definition;record.terrain_saturation=1.
	else:
		var box:=BoxMesh.new();box.size=Vector3(8,1,8);box.material=Paint.make_material(definition)
		var cpu:Mesh=Cpu.capture(box);var data:=Cook.pack({[0]:{"mesh":cpu,"source":cpu}},"","house_prefab_v1")
		var bytes:=var_to_bytes(data);var building_id:="texture_fixture_%d"%index
		record.house_prefab={"version":1,"sha256":Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
		record.building={"id":building_id,"part":"main/baked_0","role":"shell","floor":0,"floor_y":0.}
		record.prefab_locked=true;record.prefab_materials=[definition.duplicate(true)]
		var blueprint=preload("res://scripts/world3d/building_blueprint.gd")
		if not doc.map_meta.has("building_instances"):doc.map_meta.building_instances={}
		doc.map_meta.building_instances[building_id]={"version":blueprint.VERSION,"parameters":blueprint.defaults(),"position":[index*12.,0.,0.],"yaw":0.,"baked":true,"parts":{record.building.part:id},"signatures":{record.building.part:blueprint.geometry_signature(record)}}
		check(Prefab.valid(record),"valid actual frozen prefab")
	return id

func texture(id:String,kind:String)->Texture2D:
	var visual:MeshInstance3D=editor._view.get_node_or_null(id)
	if visual==null:return null
	var material:Material=visual.get_active_material(0)
	if material==null:return null
	return material.get_shader_parameter("base_albedo") if kind=="terrain" else material.albedo_texture

func run()->void:
	create_timer(120).timeout.connect(func():quit(2));Engine.max_fps=60;rpc_timeout_ms=60000
	var directory:=Paths.cache_directory("texture_owner_refresh_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var source:=directory.path_join("color.png");var image:=Image.create(32,32,false,Image.FORMAT_RGBA8);image.fill(Color(.3,.4,.8));image.save_png(source)
	var definition:={"name":"shared","color":[1.,1.,1.,1.],"roughness":.8,"texture_path":source}
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=Doc.new();session.world3d_editor_path=""
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;root.add_child(editor);editor._safety.enabled=false
	var old_budget:=Paint.cache_byte_budget;Paint.cache_byte_budget=0
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"actual HTTP editor started")
	for scenario:Array in [["terrain",false],["prefab",false],["terrain",true],["prefab",true]]:
		var kind:String=scenario[0];var prepublished:bool=scenario[1]
		image.save_png(source)
		var doc:=Doc.new();var first:=make_record(doc,kind,0,definition);var second:=make_record(doc,kind,1,definition)
		var path:=directory.path_join(kind+("_prepublished" if prepublished else "")+".gltf");check(doc.save(path)==OK,kind+": save actual two-record map")
		Paint.refresh_sources()
		await call_tool("open_world",{"path":path,"discard_changes":true})
		var state:Dictionary=editor._load_job.state()
		check(state.phase=="complete" and state.timings.preparation.started==1,kind+": full production load prepares shared pixels once")
		check(texture(first,kind)!=null and texture(first,kind)==texture(second,kind) and not Paint._textures.has(Paint.texture_key(source)),kind+": actual scene materials share the evicted texture")
		editor._load_job.queue_free()
		var gated:=RefreshJob.new();gated.editor=editor;gated.target=second;gated.changed_source=source;gated.publish_on_refresh=prepublished;editor._load_job=gated;editor.add_child(gated)
		Paint.refresh_sources()
		await call_tool("open_world",{"path":path,"discard_changes":true})
		state=gated.state()
		check(gated.interrupted and gated.attempts==2 and state.phase=="complete",kind+": actual publication loop recovers from source refresh after yielding")
		check(state.timings.preparation.started==(1 if prepublished else 2) and state.timings.preparation.ledger.jobs==0,kind+(": prepublished owner needs no replacement worker" if prepublished else ": one replacement worker and no retained leases"))
		check(texture(first,kind)!=null and texture(second,kind)!=null and texture(first,kind)!=texture(second,kind),kind+": old live material stays valid and new material uses refreshed generation")
		var readback:Image=texture(second,kind).get_image() if texture(second,kind)!=null else null
		check(readback!=null and readback.get_width()==32 and readback.get_pixel(0,0).is_equal_approx(Color.BLUE),kind+": refreshed GPU pixels match the newly written source")
		var original:Image=texture(first,kind).get_image() if texture(first,kind)!=null else null
		check(original!=null and original.get_pixel(0,0).is_equal_approx(image.get_pixel(0,0)),kind+": previously published material keeps the original pixels")
		await call_tool("save_world")
		check(editor._save_job.result.get("saved",false),kind+": actual save after refresh succeeds")
		# Replace the diagnostic gate with the ordinary production class before
		# the next case so the first-open workload remains a normal editor load.
		gated.queue_free();editor._load_job=preload("res://scripts/world_editor/load_job.gd").new();editor._load_job.editor=editor;editor.add_child(editor._load_job)
	Paint.cache_byte_budget=old_budget
	editor.queue_free();await settle()
	print("EDITOR_TEXTURE_OWNER_REFRESH_FAILED=",failed);quit(1 if failed else 0)
