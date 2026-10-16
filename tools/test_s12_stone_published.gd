extends "res://tools/test_guild_street_published_catalog.gd"
## Formal catalog read-only; both accepted S12 revisions in a new cache map.
## --receipt=<successful S12 publication JSON> --out=<fresh review directory>
const Walk=preload("res://scripts/world_editor/walk_mode.gd")
const S12Publisher=preload("res://tools/import_s12_stone_materials.gd")
const LEGACY:Dictionary={
	"s12_projecting_arch":{"file":"11feb4a7d18c9fd25cef5ca588e55f1e518141b78acc5baaf3b1a048920f43be.glb","label":"S12 外挑双柱大拱门"},
	"s12_gable_relief":{"file":"d0ca66d5b04913d4bc9ffd56fcc01bb2f4761332dc28fcd98337ad21026dd240.glb","label":"S12 山墙高窄雕饰板"}
}
var active_asset_id:=""
var active_materials:Array=[]

func gate(ok:bool,label:String)->bool:
	check(ok,label)
	return ok

func body_query(body:StaticBody3D,mask:int)->Dictionary:
	# The S2-verified query: unchanged production shapes, actual physics server,
	# both directions because Godot clockwise faces oppose the cross normal.
	var probe:Dictionary={"hit":false,"mask":mask,"attempts":0,"shapes":[]}
	for child:Node in body.get_children():
		if not child is CollisionShape3D or child.disabled or child.shape==null:continue
		var faces:=PackedVector3Array()
		if child.shape is ConcavePolygonShape3D:faces=child.shape.get_faces()
		elif child.shape is BoxShape3D:
			var box:=BoxMesh.new();box.size=child.shape.size;faces=box.get_faces()
		else:continue
		var triangle_count:int=faces.size()/3
		probe.shapes.append({"class":child.shape.get_class(),"triangles":triangle_count})
		# The arch starts with tiny bevel triangles at floor level. Keep those
		# original probes, then cover the whole unchanged shape deterministically
		# instead of treating its first 24 triangles as the entire structure.
		var samples:Array=[]
		for triangle in mini(triangle_count,24):samples.append(triangle)
		for sample in mini(triangle_count,128):
			var triangle:int=sample*triangle_count/mini(triangle_count,128)
			if not samples.has(triangle):samples.append(triangle)
		for triangle:int in samples:
			var a:Vector3=child.global_transform*faces[triangle*3]
			var b:Vector3=child.global_transform*faces[triangle*3+1]
			var c:Vector3=child.global_transform*faces[triangle*3+2]
			var normal:Vector3=(b-a).cross(c-a).normalized()
			if normal.length_squared()<.5:continue
			var center:Vector3=(a+b+c)/3.
			for direction:float in [1.0,-1.0]:
				probe.attempts+=1
				var query:=PhysicsRayQueryParameters3D.create(center+normal*.04*direction,center-normal*.04*direction,mask)
				query.hit_back_faces=true
				var hit:Dictionary=editor.get_world_3d().direct_space_state.intersect_ray(query)
				if hit.get("collider")==body:
					probe.merge({"hit":true,"triangle":triangle,"center":[center.x,center.y,center.z],"cross_normal_direction":direction},true)
					return probe
	return probe

func model_evidence(uuid:String)->Dictionary:
	var result:=super.model_evidence(uuid)
	var holder:Node3D=editor._view.get_node_or_null(NodePath(uuid))
	if holder!=null:
		var actual:=S12Publisher.actual_material_snapshot(holder,active_asset_id)
		result.actual_materials=actual.actual_materials
		result.material_pixels_match_accepted_candidate=actual.ok and S12Publisher.same_material_evidence(actual.actual_materials,active_materials)
		result.valid=result.valid and result.material_pixels_match_accepted_candidate
	var physics:Dictionary={"structural_node":active_asset_id+"_part_0","structural_bodies":0,"picking_layer_bodies":0,"walking_layer_bodies":0,"actual_picking_ray_hits":0,"actual_walking_ray_hits":0,"actual_structural_picking_ray_hit":false,"actual_structural_walking_ray_hit":false,"decorative_walking_bodies":0,"body_layers":[],"ray_probes":[]}
	for body:StaticBody3D in editor._bodies_by_uuid.get(uuid,[]):
		var visual:Node=body.get_meta("visual",null)
		var path:String=str(holder.get_path_to(visual)) if holder!=null and visual!=null else ""
		var structural:bool=visual!=null and str(visual.name)==physics.structural_node
		if structural:physics.structural_bodies+=1
		physics.body_layers.append({"visual":path,"layer":body.collision_layer,"structural":structural})
		if body.collision_layer&1:
			physics.picking_layer_bodies+=1
			var picking_probe:=body_query(body,1);picking_probe.visual=path;physics.ray_probes.append(picking_probe)
			if picking_probe.hit:
				physics.actual_picking_ray_hits+=1
				if structural:physics.actual_structural_picking_ray_hit=true
		if body.collision_layer&Walk.WALK_MASK:
			physics.walking_layer_bodies+=1
			if visual!=null and str(visual.name)==active_asset_id+"_part_1":physics.decorative_walking_bodies+=1
			var walking_probe:=body_query(body,Walk.WALK_MASK);walking_probe.visual=path;physics.ray_probes.append(walking_probe)
			if walking_probe.hit:
				physics.actual_walking_ray_hits+=1
				if structural:physics.actual_structural_walking_ray_hit=true
	physics.body_layers.sort_custom(func(a,b):return a.visual<b.visual)
	result.physics=physics
	result.valid=result.valid and physics.structural_bodies==1 and physics.actual_structural_picking_ray_hit and physics.actual_structural_walking_ray_hit and physics.decorative_walking_bodies==0
	if active_asset_id=="s12_projecting_arch" and holder!=null:
		# Existing design: 2.48 m clear column width, spring height 3.67 m.
		# Probe both travel directions through representative interior heights.
		var opening:Dictionary={"tested":0,"clear":0,"local_x":[-.8,0.,.8],"local_heights":[.25,1.4,3.0],"local_z_span":[-2.5,3.0]}
		for x:float in opening.local_x:
			for height:float in opening.local_heights:
				var from:Vector3=holder.global_transform*Vector3(x,height,-2.5)
				var to:Vector3=holder.global_transform*Vector3(x,height,3.0)
				for reverse:bool in [false,true]:
					var query:=PhysicsRayQueryParameters3D.create(to if reverse else from,from if reverse else to,Walk.WALK_MASK)
					opening.tested+=1
					if editor.get_world_3d().direct_space_state.intersect_ray(query).is_empty():opening.clear+=1
		result.opening=opening;result.valid=result.valid and opening.tested==18 and opening.clear==18
	return result

func prepare_s12()->bool:
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	if not gate(parsed is Dictionary,"S12 publication JSON object"):return false
	published=parsed
	if not gate(published.get("ok",false) and published.get("completed",false) and published.get("items") is Array and published.items.size()==2,"successful two-model formal publication"):return false
	catalog_path=canonical(str(published.get("catalog_path","")))
	if not gate(catalog_path==canonical(Paths.external_root().path_join("packs/default/assets/library.json")),"actual shared default catalog"):return false
	check(Packs.new().packs().any(func(pack):return canonical(pack.root)==catalog_path.get_base_dir().get_base_dir() and pack.shared),"normal shared pack discovery")
	var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	if not gate(raw is Array and raw.all(func(entry):return entry is Dictionary and entry.get("label") is String),"raw catalog is an array of typed entries"):return false
	var library:=Library.new(catalog_path.get_base_dir())
	check(library.entries.size()==raw.size(),"normal library retains every raw entry")
	for raw_entry:Dictionary in raw:
		for key:String in ["asset_path","prefab_path","thumbnail_path"]:
			if raw_entry.has(key):check(raw_entry[key] is String and not str(raw_entry[key]).is_absolute_path(),"relative typed disk path "+key)
	readonly_guards[receipt_path]=FileAccess.get_sha256(receipt_path);readonly_guards[catalog_path]=library._revision
	var seen:Dictionary={}
	for data:Variant in published.items:
		if not gate(data is Dictionary and data.has_all(["id","target","sha256","old_asset_path","label","category","acceptance_report","acceptance_report_sha256"]),"complete S12 publication item"):return false
		var row:Dictionary=data;var id:String=str(row.id)
		if not gate(LEGACY.has(id) and not seen.has(id),"unique permitted S12 identity "+id):return false
		seen[id]=true
		var target:=canonical(str(row.target));var old:=canonical(str(row.old_asset_path))
		if not gate(Paths.allowed(target,catalog_path.get_base_dir()) and target.get_file()==str(row.sha256)+".glb" and old==catalog_path.get_base_dir().path_join(LEGACY[id].file),"new and retained old paths confined "+id):return false
		check(FileAccess.get_sha256(target)==row.sha256,"formal current GLB accepted SHA "+id)
		check(FileAccess.get_sha256(old)==str(LEGACY[id].file).get_basename(),"old immutable GLB retained "+id)
		var matches:Array=library.entries.filter(func(entry):return entry.get("asset_path")==target)
		check(matches.size()==1 and matches[0].get("label")==LEGACY[id].label and matches[0].get("category")==row.category,"one current entry keeps original formal name "+id)
		check(library.entries.filter(func(entry):return entry.get("label")==LEGACY[id].label).size()==1 and not library.entries.any(func(entry):return entry.get("asset_path")==old),"old/new catalog label has no ambiguity "+id)
		check(FileAccess.get_sha256(row.acceptance_report)==row.acceptance_report_sha256,"same accepted review identity "+id)
		var proof:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(row.acceptance_report))
		var gpu:Dictionary=proof.get("gpu_report",{})
		check(FileAccess.get_sha256(gpu.get("path",""))==gpu.get("sha256"),"accepted GPU report SHA unchanged "+id)
		var gpu_report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(gpu.get("path","")))
		check(gpu_report.get("generator")==Compile.generator(),"current generator matches accepted candidate "+id)
		readonly_guards[gpu.path]=gpu.sha256
		var native:=Library._verified_compiled_identity(target)
		check(not native.is_empty() and native.get("source_sha")==row.sha256,"real native and current generator "+id)
		if failed>0:return false
		var entry:Dictionary=matches[0];var thumb:String=entry.thumbnail_path
		var pixels:=Image.load_from_file(thumb)
		check(pixels!=null and not pixels.is_empty() and not pixels.is_invisible(),"published production thumbnail readable "+id)
		for path:String in [target,old,thumb,row.acceptance_report]:readonly_guards[path]=FileAccess.get_sha256(path)
		audit.items.append({"id":id,"input_sha":row.sha256,"output_sha":row.sha256,"output_path":target,"old_asset_path":old,"entry":entry.duplicate(true),"formal_native_identity":native,"prior_visual_review":row.acceptance_report,"prior_visual_review_sha256":row.acceptance_report_sha256,"expected_materials":gpu_report.actual_materials})
	var map_path:=Paths.external_root().path_join("maps/medieval_river_town/map.gltf")
	if FileAccess.file_exists(map_path):readonly_guards[map_path]=FileAccess.get_sha256(map_path)
	audit.catalog_sha_at_publication=published.catalog_sha_after;audit.catalog_sha_at_verification=library._revision
	return failed==0

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if "--syntax-only" in args:print("S12_STONE_HTTP syntax only");quit();return
	var provided:Dictionary={}
	for arg:String in args:
		if arg.begins_with("--receipt=") and not provided.has("receipt"):receipt_path=canonical(arg.trim_prefix("--receipt="));provided.receipt=true
		elif arg.begins_with("--out=") and not provided.has("out"):output_dir=canonical(arg.trim_prefix("--out="));provided.out=true
		else:push_error("Unknown or duplicate argument "+arg);quit(2);return
	var confined:bool=Paths.allowed(output_dir,canonical("res://review_artifacts")) or Paths.allowed(output_dir,Paths.external_root().path_join("review_artifacts"))
	if not provided.has_all(["receipt","out"]) or not confined or FileAccess.file_exists(output_dir.path_join("editor_verification.json")) or DisplayServer.get_name()=="headless":push_error("Explicit receipt/fresh confined output and private GPU desktop required");quit(2);return
	Engine.max_fps=60;rpc_timeout_ms=120000;root.size=Vector2i(1000,720)
	audit={"checks":[],"items":[],"published":true,"formal_catalog_modified":false,"formal_map_modified":false,"real_http":true,"receipt_path":receipt_path,"generator":Compile.generator(),"runtime_identity":http_runtime_identity(),"scope":"Two revised S12 models from the real formal library in an owned temporary map. No existing map migration or new visual approval claim.","mcp_limit":"Current 3D MCP has catalog discovery/placement but no generic external GLB import. Publication uses the normal UI AssetLibrary importer."}
	create_timer(1800).timeout.connect(func():audit.timeout=true;flush_report();quit(2))
	if not prepare_s12():flush_report();quit(1);return
	fixture_directory=Paths.cache_directory("s12_stone_verify_%d"%Time.get_ticks_usec())
	check(not DirAccess.dir_exists_absolute(fixture_directory),"new owned temporary map folder")
	check(DirAccess.make_dir_recursive_absolute(fixture_directory)==OK,"create owned temporary folder")
	var map_path:=fixture_directory.path_join("map.gltf")
	var doc:=Doc.new();check(doc.save(map_path)==OK,"empty disposable map saved")
	if failed>0:flush_report();quit(1);return
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=map_path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=fixture_directory.path_join("drafts");root.add_child(editor)
	if editor._thumbnails!=null:editor._thumbnails.set_process(false)
	await wait_loaded();editor._safety.enabled=false
	var probe:=TCPServer.new();port=29950
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real loopback 3D HTTP ready")
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var names:Array=(await rpc("tools/list")).get("result",{}).get("tools",[]).map(func(tool):return tool.name)
	audit.tool_names=names;audit.port=port;audit.isolated_map=map_path
	for tool:String in ["list_assets","place_asset","select_objects","delete_selection","list_building_components","save_world","open_world","undo","redo"]:check(names.has(tool),"tool discovered by name "+tool)
	for row:Dictionary in audit.items:
		active_asset_id=row.id
		active_materials=row.expected_materials
		await verify_item(row,map_path)
		for phase_name:String in ["before_save","after_reopen"]:
			check(row.get(phase_name,{}).get("material_pixels_match_accepted_candidate",false),"actual editor material parameters and decoded pixels match accepted candidate "+row.id+" "+phase_name)
			var physical:Dictionary=row.get(phase_name,{}).get("physics",{})
			check(physical.get("actual_structural_picking_ray_hit",false),"structural stone itself has real picking hit "+row.id+" "+phase_name)
			check(physical.get("actual_structural_walking_ray_hit",false),"structural stone itself has real walking collision "+row.id+" "+phase_name)
			check(physical.get("decorative_walking_bodies",-1)==0,"nonblocking decorative part remains nonblocking "+row.id+" "+phase_name)
			if row.id=="s12_projecting_arch":check(row.get(phase_name,{}).get("opening",{}).get("clear")==18,"arch passage stays clear in both directions "+phase_name)
		if failed>0:break
	check(equivalent(audit.runtime_identity,http_runtime_identity()),"runtime implementation unchanged during verification")
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_doc=null;session.world3d_editor_path=""
	for path:String in readonly_guards:check(FileAccess.get_sha256(path)==readonly_guards[path],"formal library/source/retained-old/proof/map unchanged "+path.get_file())
	audit.completed=failed==0;audit.verified_count=audit.items.filter(func(row):return row.get("http_passed",false)).size()
	check(audit.verified_count==2,"both S12 revisions verified")
	flush_report();print("S12_STONE_HTTP failures=",failed);quit(0 if failed==0 else 1)
