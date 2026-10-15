extends "res://tools/test_guild_street_published_catalog.gd"
## Single-model specialization; no historical 64-item manifest/run is invoked.
## --receipt=<S2 publication.json> --out=<new review directory> --syntax-only
## Real shared catalog is read-only. Only a new cache-owned map is modified.
const Walk=preload("res://scripts/world_editor/walk_mode.gd")

func body_query(body:StaticBody3D,mask:int)->bool:
	# Probe actual physics-server triangles, not inferred extras or AABB overlap.
	# Missing rmmo_collision means physical under the production Walk contract.
	for child:Node in body.get_children():
		if not child is CollisionShape3D or child.disabled or child.shape==null:continue
		# Shape debug meshes contain wire lines, not necessarily triangles.
		# Read the exact production concave collision faces instead.
		var faces:=PackedVector3Array()
		if child.shape is ConcavePolygonShape3D:faces=child.shape.get_faces()
		elif child.shape is BoxShape3D:
			var box:=BoxMesh.new();box.size=child.shape.size;faces=box.get_faces()
		else:continue
		for triangle in mini(faces.size()/3,24):
			var a:Vector3=child.global_transform*faces[triangle*3]
			var b:Vector3=child.global_transform*faces[triangle*3+1]
			var c:Vector3=child.global_transform*faces[triangle*3+2]
			var normal:Vector3=(b-a).cross(c-a).normalized()
			if normal.length_squared()<.5:continue
			var center:Vector3=(a+b+c)/3.
			# Godot's clockwise front faces need not agree with the mathematical
			# cross-product normal. Probe both directions against the unchanged
			# production single-sided shape; never enable backface collision on it.
			for direction:float in [1.0,-1.0]:
				var query:=PhysicsRayQueryParameters3D.create(center+normal*.04*direction,center-normal*.04*direction,mask)
				query.hit_back_faces=true
				var hit:Dictionary=editor.get_world_3d().direct_space_state.intersect_ray(query)
				if hit.get("collider")==body:
					print("PHYSICS_RAY_HIT body=",body.name," mask=",mask," cross_normal_direction=",direction)
					return true
	return false

func model_evidence(uuid:String)->Dictionary:
	var result:=super.model_evidence(uuid)
	var physics:Dictionary={"picking_layer_bodies":0,"walking_layer_bodies":0,"actual_picking_ray_hits":0,"actual_walking_ray_hits":0,"postbody_visuals":[],"actual_postbody_picking_ray_hit":false,"actual_postbody_walking_ray_hit":false,"body_layers":[]}
	for body:StaticBody3D in editor._bodies_by_uuid.get(uuid,[]):
		var visual:Node=body.get_meta("visual",null)
		var path:String=str(editor._view.get_node(uuid).get_path_to(visual)) if visual!=null else ""
		# Match the authored structural mesh exactly. Ribbon/cloth collision is
		# recorded independently and cannot satisfy the PostBody requirement.
		var is_postbody:bool=visual!=null and str(visual.name)=="PostBody" and path.get_file()=="PostBody"
		if is_postbody:physics.postbody_visuals.append(path)
		physics.body_layers.append({"visual":path,"layer":body.collision_layer,"is_postbody":is_postbody})
		if body.collision_layer&1:
			physics.picking_layer_bodies+=1
			if body_query(body,1):
				physics.actual_picking_ray_hits+=1
				if is_postbody:physics.actual_postbody_picking_ray_hit=true
		if body.collision_layer&Walk.WALK_MASK:
			physics.walking_layer_bodies+=1
			if body_query(body,Walk.WALK_MASK):
				physics.actual_walking_ray_hits+=1
				if is_postbody:physics.actual_postbody_walking_ray_hit=true
	physics.body_layers.sort_custom(func(a,b):return a.visual<b.visual)
	physics.postbody_visuals.sort()
	result.physics=physics
	result.valid=result.valid and physics.actual_picking_ray_hits>0 and physics.actual_walking_ray_hits>0 and physics.actual_postbody_picking_ray_hit and physics.actual_postbody_walking_ray_hit
	return result

func prepare_single()->bool:
	check(FileAccess.file_exists(receipt_path),"S2 import receipt exists")
	if failed>0:return false
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	check(parsed is Dictionary,"publication receipt is a JSON object")
	if failed>0:return false
	published=parsed
	var rows:Variant=published.get("items")
	check(published.get("ok",false) and published.get("completed",false) and rows is Array and rows.size()==1 and rows[0] is Dictionary,"completed single-model publication")
	if failed>0:return false
	catalog_path=canonical(str(published.get("catalog_path","")))
	check(catalog_path==canonical(Paths.external_root().path_join("packs/default/assets/library.json")),"actual default shared catalog")
	check(Packs.new().packs().any(func(pack):return canonical(pack.root)==catalog_path.get_base_dir().get_base_dir() and pack.shared),"normal shared pack discovery")
	var row:Dictionary=published.items[0]
	check(row.has_all(["id","target","sha256","label","category","acceptance_report","acceptance_report_sha256"]) and str(row.get("id","")).is_valid_filename(),"complete single-model receipt fields and safe ID")
	if failed>0:return false
	var target:=canonical(str(row.target))
	check(Paths.allowed(target,catalog_path.get_base_dir()) and target.get_file()==str(row.sha256)+".glb","immutable shared target confined")
	if failed>0:return false
	check(FileAccess.get_sha256(target)==row.sha256,"formal GLB matches accepted source SHA")
	var library:=Library.new(catalog_path.get_base_dir())
	var matches:Array=library.entries.filter(func(entry):return canonical(str(entry.get("asset_path","")))==target)
	check(matches.size()==1 and matches[0].get("label")==row.label and matches[0].get("category")==row.category,"single exact formal entry")
	check(FileAccess.get_sha256(row.acceptance_report)==row.acceptance_report_sha256,"accepted review remains unchanged")
	var native:=Library._verified_compiled_identity(target)
	check(not native.is_empty() and native.get("source_sha")==row.sha256,"actual native payload and current generator verified")
	if failed>0:return false
	var thumb:String=matches[0].thumbnail_path
	var image:=Image.load_from_file(thumb)
	check(image!=null and not image.is_empty() and not image.is_invisible(),"formal thumbnail is readable")
	for path:String in [receipt_path,target,catalog_path,thumb,row.acceptance_report]:readonly_guards[path]=FileAccess.get_sha256(path)
	var user_map:=Paths.external_root().path_join("maps/medieval_river_town/map.gltf")
	if FileAccess.file_exists(user_map):readonly_guards[user_map]=FileAccess.get_sha256(user_map)
	audit.catalog_sha_at_publication=published.catalog_sha_after
	audit.catalog_sha_at_verification=library._revision
	audit.catalog_revision_note="Later unrelated catalog additions are allowed; this process never writes the catalog. The selected entry and its accepted identity must still match exactly."
	audit.items=[{"id":row.id,"input_sha":row.sha256,"output_sha":row.sha256,"output_path":target,"entry":matches[0].duplicate(true),"formal_native_identity":native,"prior_visual_review":row.acceptance_report,"prior_visual_review_sha256":row.acceptance_report_sha256}]
	return failed==0

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if "--syntax-only" in args:print("S2_GREEN_POST_HTTP syntax only");quit();return
	var provided:Dictionary={}
	for arg:String in args:
		if arg.begins_with("--receipt=") and not provided.has("receipt"):receipt_path=canonical(arg.trim_prefix("--receipt="));provided.receipt=true
		elif arg.begins_with("--out=") and not provided.has("out"):output_dir=canonical(arg.trim_prefix("--out="));provided.out=true
		else:push_error("Unknown argument "+arg);quit(2);return
	if not provided.has_all(["receipt","out"]) or DisplayServer.get_name()=="headless":push_error("Explicit receipt/out and private GPU desktop required");quit(2);return
	var allowed:bool=Paths.allowed(output_dir,canonical("res://review_artifacts")) or Paths.allowed(output_dir,Paths.external_root().path_join("review_artifacts"))
	if not allowed or FileAccess.file_exists(output_dir.path_join("editor_verification.json")):push_error("A fresh confined report path is required");quit(2);return
	Engine.max_fps=60;rpc_timeout_ms=120000;root.size=Vector2i(1000,720)
	audit={"checks":[],"items":[],"published":true,"formal_catalog_modified":false,"formal_map_modified":false,"real_http":true,"receipt_path":receipt_path,"generator":Compile.generator(),"runtime_identity":http_runtime_identity(),"scope":"One reviewed S2 model through the actual formal catalog. Temporary-map placement only; no street placement, whole-city or new visual approval claim.","mcp_limit":"Current 3D MCP exposes catalog discovery and placement, not generic external GLB file import. Publication uses the same AssetLibrary importer as UI."}
	create_timer(1200).timeout.connect(func():audit.timeout=true;flush_report();quit(2))
	if not prepare_single():flush_report();quit(1);return
	fixture_directory=Paths.cache_directory("s2_green_post_verify_%d"%Time.get_ticks_usec())
	check(not DirAccess.dir_exists_absolute(fixture_directory),"new owned fixture directory")
	check(DirAccess.make_dir_recursive_absolute(fixture_directory)==OK,"create owned fixture")
	var map_path:=fixture_directory.path_join("map.gltf")
	var doc:=Doc.new();check(doc.save(map_path)==OK,"empty disposable map saved")
	if failed>0:flush_report();quit(1);return
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=map_path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=fixture_directory.path_join("drafts");root.add_child(editor)
	if editor._thumbnails!=null:editor._thumbnails.set_process(false)
	await wait_loaded();editor._safety.enabled=false
	var probe:=TCPServer.new();port=29940
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real loopback 3D HTTP ready")
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var names:Array=(await rpc("tools/list")).get("result",{}).get("tools",[]).map(func(tool):return tool.name)
	audit.tool_names=names;audit.port=port;audit.isolated_map=map_path
	for name_:String in ["list_assets","place_asset","select_objects","delete_selection","save_world","open_world","undo","redo"]:check(names.has(name_),"tool discovered by name "+name_)
	var row:Dictionary=audit.items[0]
	await verify_item(row,map_path)
	for phase_name:String in ["before_save","after_reopen"]:
		var physical:Dictionary=row.get(phase_name,{}).get("physics",{})
		check(physical.get("actual_picking_ray_hits",0)>0,"physics server confirms real editor picking "+phase_name)
		check(physical.get("actual_walking_ray_hits",0)>0,"physics server confirms real walking collision "+phase_name)
		check(physical.get("actual_postbody_picking_ray_hit",false),"PostBody itself has an actual editor picking ray hit "+phase_name)
		check(physical.get("actual_postbody_walking_ray_hit",false),"PostBody itself has an actual walking collision ray hit "+phase_name)
	check(equivalent(audit.runtime_identity,http_runtime_identity()),"runtime implementation unchanged")
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_doc=null;session.world3d_editor_path=""
	for path:String in readonly_guards:check(FileAccess.get_sha256(path)==readonly_guards[path],"formal catalog/model/thumbnail/review/map unchanged "+path.get_file())
	audit.completed=failed==0;audit.verified_count=1 if failed==0 else 0
	flush_report();print("S2_GREEN_POST_HTTP complete failures=",failed);quit(0 if failed==0 else 1)
