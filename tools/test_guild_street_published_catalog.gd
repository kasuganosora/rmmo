extends "res://tools/test_guild_reference_import.gd"
## Read-only formal catalog acceptance for the 64 already reviewed guild/street assets.
## Writes only a newly owned map under cache/world3d and an explicit review report.
## --receipt=<published receipt.json> --out=<review_artifacts/...> [--only=id,id]
## --syntax-only is the only supported headless mode. GPU: private desktop runner.
const Packs=preload("res://scripts/world_editor/resource_pack_catalog.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var receipt_path:="D:/code/rmmo_runtime/review_artifacts/guild_reference_recheck_20261013/formal_import/receipt.json"
var published:Dictionary={}
var readonly_guards:Dictionary={}
var fixture_directory:=""
var catalog_path:=""

func canonical(path:String)->String:
	return ProjectSettings.globalize_path(path).replace("\\","/").simplify_path()

func http_runtime_identity()->Dictionary:
	var identity:=super.http_runtime_identity()
	for path:String in ["scripts/world3d/streetlamp_lights.gd","scripts/world3d/house_candle_lights.gd","scripts/world_editor/picking_lod_policy.gd","scripts/world_editor/walk_mode.gd"]:
		identity[path]=FileAccess.get_sha256("res://"+path)
	return identity

func flush_report()->void:
	audit.failures=failed;audit.passed=failed==0
	write_json(output_dir.path_join("editor_verification.json"),audit)

func prepare_published_catalog()->bool:
	var initial:=failed
	check(FileAccess.file_exists(receipt_path),"existing formal publication receipt")
	if failed!=initial:return false
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	check(value is Dictionary and value.get("ok",false),"receipt records successful formal publication")
	if failed!=initial:return false
	published=value
	catalog_path=canonical(str(published.get("catalog_path","")))
	var default_catalog:=Paths.external_root().path_join("packs/default/assets/library.json")
	check(catalog_path==canonical(default_catalog),"receipt targets the actual shared default catalog")
	check(FileAccess.get_sha256(catalog_path)==published.get("catalog_sha_after"),"fresh formal catalog revision matches receipt")
	var pack_root:=catalog_path.get_base_dir().get_base_dir()
	check(Packs.new().packs().any(func(pack):return canonical(pack.root)==pack_root and pack.shared),"formal shared pack is discoverable without injected catalogs")
	var rows:Variant=published.get("items")
	check(rows is Array and rows.size()==64,"publication receipt contains exactly 64 accepted assets")
	if failed!=initial:return false
	readonly_guards[receipt_path]=FileAccess.get_sha256(receipt_path)
	readonly_guards[catalog_path]=FileAccess.get_sha256(catalog_path)
	var library:=Library.new(catalog_path.get_base_dir())
	var seen:Dictionary={}
	var targets:Dictionary={}
	for item:Dictionary in rows:
		var id:=str(item.get("id",""));var target:=canonical(str(item.get("target","")))
		var sha:=str(item.get("sha256",""));var label:=str(item.get("label",""))
		check(not id.is_empty() and not seen.has(id),"unique published model ID "+id);seen[id]=true
		var safe:bool=Paths.allowed(target,catalog_path.get_base_dir()) and target.get_file()==sha+".glb" and sha.length()==64
		check(safe and not targets.has(target),"unique immutable published destination "+id);targets[target]=true
		if not safe:continue
		check(FileAccess.get_sha256(target)==sha,"formal GLB exact accepted SHA "+id)
		readonly_guards[target]=sha
		var matches:Array=library.entries.filter(func(entry):return canonical(str(entry.get("asset_path","")))==target)
		check(matches.size()==1 and matches[0].get("label")==label and matches[0].get("category")==item.get("category"),"formal catalog exact name/category/path "+id)
		if matches.size()!=1:continue
		var entry:Dictionary=matches[0]
		var thumb:=canonical(str(entry.get("thumbnail_path","")))
		var pixels:Image=Image.load_from_file(thumb) if FileAccess.file_exists(thumb) else null
		check(pixels!=null and not pixels.is_empty() and not pixels.is_invisible(),"published thumbnail readable and nonempty "+id)
		if pixels!=null:readonly_guards[thumb]=FileAccess.get_sha256(thumb)
		# Validate the real shared native product without retaining a second decoded
		# model beside the editor's live instance. Placement below uses normal loading.
		var native:Dictionary=Library._verified_compiled_identity(target)
		check(not native.is_empty() and native.get("source_sha")==sha,"formal native product checksum and current generator "+id)
		var row:Dictionary={"id":id,"input_sha":sha,"output_sha":sha,"output_path":target,"entry":entry.duplicate(true),"formal_native_identity":native,"thumbnail_path":thumb,"prior_visual_review":"Exact source SHA reviewed before publication; this check covers catalog/runtime/editor persistence only."}
		if selected.is_empty() or id in selected:audit.items.append(row)
	check(not audit.items.is_empty(),"nonempty verification selection")
	audit.published_count=rows.size();audit.catalog_entries=library.entries.size();audit.catalog_sha=published.catalog_sha_after
	return failed==initial

func model_evidence(uuid:String)->Dictionary:
	var holder:Node=editor._view.get_node_or_null(NodePath(uuid))
	var result:Dictionary={"meshes":0,"surfaces":0,"vertices":0,"materials":0,"picking_shapes":0,"collision_bodies":0,"body_visuals":[],"valid":holder!=null}
	if holder==null:return result
	for mesh_node:MeshInstance3D in Paint.meshes(holder):
		if mesh_node.mesh==null:result.valid=false;continue
		result.meshes+=1
		for slot in mesh_node.mesh.get_surface_count():
			result.surfaces+=1
			# Reopened static batches retain GroundCpuMesh authoring data while
			# the derived renderer owns the GPU mesh. ArrayMesh-only accessors
			# cannot be called on that valid Mesh implementation.
			if mesh_node.mesh is ArrayMesh:result.vertices+=mesh_node.mesh.surface_get_array_len(slot)
			else:result.vertices+=mesh_node.mesh.surface_get_arrays(slot)[Mesh.ARRAY_VERTEX].size()
			var material:Material=mesh_node.get_active_material(slot)
			if material==null:result.valid=false
			else:result.materials+=1
	for body:Node in editor._bodies_by_uuid.get(uuid,[]):
		result.collision_bodies+=1
		var visual:Node=body.get_meta("visual",null)
		if visual!=null:result.body_visuals.append(str(holder.get_path_to(visual)))
		for child:Node in body.get_children():
			if child is CollisionShape3D and child.shape!=null:result.picking_shapes+=1
	result.body_visuals.sort()
	result.valid=result.valid and result.meshes>0 and result.materials>0 and result.vertices>0 and result.picking_shapes>0
	return result

func test_component_id(row:Dictionary)->String:
	for member:Dictionary in row.components:
		if not str(member.id).contains("architecture:"):return str(member.id)
	return ""

func verify_item(row:Dictionary,map_path:String)->void:
	var initial:=failed
	audit.active={"id":row.id,"phase":"formal_catalog_http"};flush_report()
	var listing:=await call_tool("list_assets",{"query":row.entry.label,"limit":200})
	var matches:Array=listing.get("assets",[]).filter(func(item):return canonical(str(item.get("asset_id","")))==row.output_path and item.get("name")==row.entry.label)
	check(matches.size()==1,"normal shared catalog real HTTP search "+row.id)
	if matches.size()!=1:return
	check(matches[0].get("thumbnail",{}).get("status")=="ready","real HTTP published thumbnail ready "+row.id)
	check(editor._doc.records.is_empty(),"new asset starts in empty owned test map "+row.id)
	var snapshot:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("place_asset",{"asset_id":"invalid_published_guild_asset","position":[0,0,0]},false)
	check(equivalent(snapshot,editor._doc.recovery_snapshot()),"invalid placement leaves author state unchanged "+row.id)
	var placed:=await call_tool("place_asset",{"asset_id":row.output_path,"position":[0,0,0]})
	check(placed.get("ids",[]).size()==1 and editor._doc.records.size()==1,"place exact published asset "+row.id)
	if editor._doc.records.size()!=1:return
	var uuid:String=editor._doc.records[0].uuid;row.test_uuid=uuid
	await wait_loaded(uuid)
	await call_tool("select_objects",{"ids":[uuid]})
	check(editor._selection_tools.ids==[uuid],"selection retains the published instance UUID "+row.id)
	row.before_save=model_evidence(uuid)
	check(row.before_save.valid,"real rendered mesh/material and editor picking "+row.id)
	check(editor._doc._find(uuid).get("asset_path")==row.output_path,"instance references formal content-addressed GLB "+row.id)
	await call_tool("undo");await wait_loaded()
	check(editor._doc.records.is_empty(),"published placement undo "+row.id)
	await call_tool("redo");await wait_loaded(uuid)
	check(editor._doc.records.size()==1 and model_evidence(uuid).valid,"published placement redo resources and identity "+row.id)
	var components:=await call_tool("list_building_components",{"id":uuid})
	row.component_count=components.get("components",[]).size()
	row.components=components.get("components",[])
	if row.id=="axel_guild_repaired":check(row.component_count==37,"formal main guild exposes all 37 movable components")
	var component:=test_component_id(row)
	if not component.is_empty():
		var undo_count:int=editor._doc._undo.size()
		await call_tool("set_building_component_state",{"id":uuid,"component_id":component,"open":0.5})
		check(editor._doc._undo.size()==undo_count+1,"published component state is one undo transaction "+row.id)
		for body:StaticBody3D in editor._bodies_by_uuid.get(uuid,[]):
			check(body.global_transform.is_equal_approx(body.get_meta("visual").global_transform),"published moving collision follows visual "+row.id)
		var hinge_snapshot:Dictionary=editor._doc.recovery_snapshot()
		await call_tool("set_building_component_state",{"id":uuid,"component_id":component,"open":2.0},false)
		check(equivalent(hinge_snapshot,editor._doc.recovery_snapshot()),"invalid open amount leaves state unchanged "+row.id)
		await call_tool("undo");await call_tool("redo")
		row.tested_component=component
	var authored:Dictionary=editor._doc.recovery_snapshot()
	var saved:=await call_tool("save_world",{"path":map_path})
	while editor._save_job.active:await process_frame
	row.save_result=saved
	await call_tool("open_world",{"path":map_path});await wait_loaded(uuid)
	check(equivalent(authored.records,editor._doc.records) and equivalent(authored.map_meta,editor._doc.map_meta),"save and real editor reopen preserve complete author state "+row.id)
	check(editor._doc.missing_assets().is_empty(),"formal source dependencies resolve after reopen "+row.id)
	row.after_reopen=model_evidence(uuid)
	check(row.after_reopen.valid and equivalent(row.before_save,row.after_reopen),"saved published mesh/material/collision reopens unchanged "+row.id)
	check(not row.after_reopen.body_visuals.any(func(path):return str(path).ends_with("/AuthoredLightFlame") or str(path).ends_with("/StreetlampHalo")),"derived light effects never become picking or walking bodies "+row.id)
	if not component.is_empty():
		var reopened_record:Dictionary=editor._doc._find(uuid)
		# Authored imported buildings use the generic building contract; legacy
		# guild fixtures use model_component_states. Inspect the correct stored
		# field and the live component instead of mistaking valid new saves for loss.
		var state_key:String="model_building_states" if reopened_record.has("model_building") else "model_component_states"
		row.activity_state_field=state_key
		row.activity_state_after_reopen=reopened_record.get(state_key,{})
		check(row.activity_state_after_reopen.get(component)==0.5,"published activity state persists "+row.id)
		var live_components:=Components.rows(editor._view.get_node(NodePath(uuid)))
		check(live_components.any(func(member):return member.get("id")==component and member.get("open")==0.5),"reopened rendered component uses persisted activity "+row.id)
	var reopened=Doc.open_file(map_path)
	check(reopened!=null and reopened.records.size()==1 and reopened.records[0].get("asset_path")==row.output_path,"disk document references the formal catalog source "+row.id)
	await call_tool("select_objects",{"ids":[uuid]});await call_tool("delete_selection");await wait_loaded()
	check(editor._doc.records.is_empty(),"delete affects owned fixture only "+row.id)
	row.http_passed=failed==initial
	write_json(output_dir.path_join("items").path_join(str(row.id)+".json"),row)
	audit.erase("active");flush_report()

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if "--syntax-only" in args:print("GUILD_STREET_PUBLISHED syntax only");quit();return
	for arg:String in args:
		if arg.begins_with("--receipt="):receipt_path=canonical(arg.trim_prefix("--receipt="))
		if arg.begins_with("--out="):output_dir=canonical(arg.trim_prefix("--out="))
		if arg.begins_with("--only="):selected=arg.trim_prefix("--only=").split(",",false)
	if output_dir=="D:/code/rmmo_runtime/review_artifacts/guild_reference_import_20261013":output_dir="D:/code/rmmo_runtime/review_artifacts/guild_reference_recheck_20261013/formal_import"
	var confined:bool=Paths.allowed(output_dir,"D:/code/rmmo/review_artifacts") or Paths.allowed(output_dir,"D:/code/rmmo_runtime/review_artifacts")
	if not confined or DisplayServer.get_name()=="headless":push_error("Explicit review output and private GPU desktop required");quit(2);return
	Engine.max_fps=60;rpc_timeout_ms=120000;root.size=Vector2i(1000,720)
	audit={"checks":[],"items":[],"published":true,"formal_catalog_modified":false,"formal_map_modified":false,"real_http":true,"receipt_path":receipt_path,"generator":Compile.generator(),"runtime_identity":http_runtime_identity(),"scope":"Normal formal shared catalog, one asset at a time in a new temporary map. Reuses same-SHA material, LOD, full activity and traversal reviews. No actual city placement or whole-map performance claim."}
	create_timer(3600).timeout.connect(func():audit.timeout=true;flush_report();quit(2))
	if not prepare_published_catalog():flush_report();quit(1);return
	fixture_directory=Paths.cache_directory("guild_street_published_verify_%d"%Time.get_ticks_usec())
	check(not DirAccess.dir_exists_absolute(fixture_directory),"fresh owned fixture directory")
	check(DirAccess.make_dir_recursive_absolute(fixture_directory)==OK,"create temporary fixture directory")
	var map_path:=fixture_directory.path_join("map.gltf")
	var doc:=Doc.new();check(doc.save(map_path)==OK,"new empty temporary verification map")
	if failed>0:flush_report();quit(1);return
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=map_path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=fixture_directory.path_join("drafts");root.add_child(editor)
	# Existing published thumbnails are read by prepare_published_catalog. Stop
	# auto-repair so this verification cannot write shared catalog thumbnails.
	if editor._thumbnails!=null:editor._thumbnails.set_process(false)
	await wait_loaded();editor._safety.enabled=false
	var probe:=TCPServer.new();port=29910
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"private editor exposes current 3D HTTP on loopback")
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var tools_:Array=(await rpc("tools/list")).get("result",{}).get("tools",[])
	var names:Array=tools_.map(func(tool):return tool.name)
	audit.tool_names=names;audit.port=port;audit.isolated_map=map_path
	for name_:String in ["list_assets","place_asset","select_objects","list_building_components","set_building_component_state","save_world","open_world","undo","redo"]:check(names.has(name_),"current tool discovery "+name_)
	var unfiltered:Array=[];var offset:=0;var total:=1
	while offset<total:
		var page:=await call_tool("list_assets",{"limit":200,"offset":offset})
		total=int(page.get("total",0));unfiltered.append_array(page.get("assets",[]));offset+=200
		if not page.get("ok",false):break
	for row:Dictionary in audit.items:
		check(unfiltered.any(func(entry):return canonical(str(entry.get("asset_id","")))==row.output_path),"unfiltered editor catalog includes published asset "+row.id)
	audit.http_unfiltered_catalog_total=total
	for row:Dictionary in audit.items:
		await verify_item(row,map_path)
		if failed>0:break
	check(equivalent(audit.runtime_identity,http_runtime_identity()),"editor runtime code unchanged during verification")
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_doc=null;session.world3d_editor_path=""
	for path:String in readonly_guards:check(FileAccess.get_sha256(path)==readonly_guards[path],"formal source/catalog/thumbnail/receipt remains byte-identical "+path.get_file())
	audit.completed=true;audit.verified_count=audit.items.filter(func(row):return row.get("http_passed",false)).size()
	check(audit.verified_count==audit.items.size(),"all requested published assets passed real editor verification")
	flush_report();print("GUILD_STREET_PUBLISHED complete failures=",failed);quit(0 if failed==0 else 1)
