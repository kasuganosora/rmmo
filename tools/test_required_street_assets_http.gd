extends "res://tools/test_world3d_mcp.gd"
## Production compiler, actual 3D editor API and native map reopen, isolated root.
const DEST="D:/code/rmmo_runtime/review_artifacts/required_street_assets_20261013"
const Library=preload('res://scripts/world_editor/asset_library.gd')
const Compile=preload('res://scripts/world3d/compiled_asset_cache.gd')
const Paint=preload('res://scripts/world3d/surface_materials.gd')
func wait_loaded()->void:
	for i in 9000:
		await process_frame
		if i>30 and not editor.saving():return
	check(false,'editor load timeout')
func run()->void:
	create_timer(850).timeout.connect(func():push_error('Required assets HTTP timeout');quit(2))
	Engine.max_fps=60;rpc_timeout_ms=90000;root.size=Vector2i(1100,800)
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('D:/code/rmmo_runtime/art_sources/required_street_assets_20261013/manifest.json'))
	var folder:=Paths.cache_directory('required_street_20261013_%d'%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var lib:=Library.new(folder+'/assets');var entries:Array=[];var products:Array=[]
	for row:Dictionary in data.assets:
		var imported:=lib.import_file(row.path);check(imported.get('ok',false),'real library import '+str(row.id))
		if not imported.get('ok',false):continue
		var entry:Dictionary=imported.entry;entries.append(entry)
		check(FileAccess.get_sha256(entry.asset_path)==row.sha256,'isolated exact source '+str(row.id))
		var result:=Compile.build(entry.asset_path);check(result.get('ok',false),'production compiled native '+str(row.id))
		products.append({'id':row.id,'source_sha':row.sha256,'entry':entry,'compiled':result})
	var path:=folder+'/map.gltf';var doc:=Doc.new();check(doc.save(path)==OK,'empty isolated map')
	var session=preload('res://scripts/net/net.gd').session();session.world3d_editor_path=path;session.world3d_editor_doc=doc
	editor=preload('res://scripts/world_editor/world_editor.gd').new();editor._mcp_autostart=false;editor._draft_directory=folder+'/drafts';root.add_child(editor);await wait_loaded();editor._safety.enabled=false
	editor._assets=lib;editor._shared_assets=[]
	var probe:=TCPServer.new();port=29780
	while probe.listen(port,'127.0.0.1')!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,'loopback HTTP ready')
	await rpc('initialize',{'protocolVersion':'2025-03-26'})
	var discovery:=await rpc('tools/list');check(discovery.result.tools.any(func(t):return t.name=='place_asset'),'3D asset tools discovered')
	var snapshot=editor._doc.recovery_snapshot();await call_tool('place_asset',{'asset_id':'missing_required_asset','position':[0,0,0]},false);check(editor._doc.recovery_snapshot()==snapshot,'invalid placement has no side effects')
	for i in entries.size():
		var e:Dictionary=entries[i]
		var listed:=await call_tool('list_assets',{'query':e.label})
		check(listed.get('assets',[]).size()==1,'exact isolated asset discovery '+e.label)
		if listed.get('assets',[]).size()!=1:quit(1);return
		await call_tool('place_asset',{'asset_id':listed.assets[0].asset_id,'position':[float(i%4)*10.,0.,float(i/4)*14.]});await wait_loaded()
		check(editor._doc.records.size()==i+1,'placed independent asset '+str(i))
	check(editor._doc.records.size()==11,'all 11 independent assets installed in temporary map')
	var last_id:String=editor._doc.records[-1].uuid
	await call_tool('select_objects',{'ids':[last_id]});check(editor._view.get_node_or_null(last_id)!=null,'imported tree exists as independently selectable instance')
	var body_count:=0
	for bodies in editor._bodies_by_uuid.values():body_count+=bodies.size()
	check(body_count>=11,'real editor collision bodies created')
	await call_tool('undo');await wait_loaded();check(editor._doc.records.size()==10,'placement undo')
	await call_tool('redo');await wait_loaded();check(editor._doc.records.size()==11,'placement redo')
	await call_tool('save_world');await call_tool('open_world',{'path':path});await wait_loaded()
	check(editor._doc.records.size()==11 and editor._doc.missing_assets().is_empty(),'real editor save/open retains all dependencies')
	var reopened=Doc.open_file(path);check(reopened!=null and reopened.records.size()==11,'native document reopen')
	var node:Node=editor._view.get_node_or_null(last_id)
	if node!=null:
		var ms:=Paint.meshes(node);check(ms.any(func(m):return m.get_meta('extras',{}).has('rmmo_wind')),'wind survives editor reopen');check(ms.any(func(m):return m.get_meta('extras',{}).has('rmmo_visibility_range')),'LOD survives editor reopen')
	else:check(false,'tree instance reappears after map reopen')
	var report:={'date':'2026-10-13','failures':failed,'real_http':true,'isolated_map':path,'generator':Compile.generator(),'items':products,'editor_collision_bodies':body_count,'production_map_modified':false,'published':false}
	DirAccess.make_dir_recursive_absolute(DEST);FileAccess.open(DEST+'/editor_http.json',FileAccess.WRITE).store_string(JSON.stringify(report,'  '))
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_doc=null;session.world3d_editor_path=''
	print('REQUIRED_STREET_HTTP failures=',failed);quit(0 if failed==0 else 1)
