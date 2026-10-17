extends "res://tools/test_guild_reference_import.gd"
## Same audited source/native semantics and real HTTP contract, today's 11 assets.
## The originals and all formal maps/catalogues remain untouched.
const MANIFEST="D:/code/rmmo_runtime/art_sources/required_street_assets_20261013/review_v2/manifest.json"
const DEST="D:/code/rmmo_runtime/review_artifacts/required_street_recheck_20261013"
var original_content_override:=""

func configure_isolated_content(prior:Dictionary)->Dictionary:
	# Scope the real import/compiler/editor together. A catalogue directory by
	# itself does not scope Compiled.directory(), whose normal default is the
	# process content root. Never raise its 8 GiB limit or evict user products.
	var shared_root:=Paths.external_root()
	var content_root:=Paths.cache_directory('required_street_native_scope_%d'%Time.get_ticks_usec())
	var prior_root:String=str(prior.get('content_root',''))
	var reusable:bool=prior.get('generator','')==Compile.generator() and not prior_root.is_empty() and Paths.allowed(prior_root,shared_root) and prior_root.get_file().begins_with('required_street_native_scope_') and DirAccess.dir_exists_absolute(prior_root)
	if reusable:content_root=prior_root
	else:prior={}
	check(DirAccess.make_dir_recursive_absolute(content_root)==OK,'isolated external content root created')
	var manager:=root.get_node('AssetManager')
	original_content_override=manager.content_root_override
	manager.content_root_override=content_root
	check(Paths.external_root()==content_root and Compile.directory().begins_with(content_root+'/'),'production root and native cache scoped together')
	audit.content_root=content_root;audit.shared_content_root=shared_root
	audit.native_cache_directory=Compile.directory();audit.native_cache_limit_bytes=Compile.MAX_CACHE_BYTES
	audit.isolation_note='Process-only existing AssetManager content_root_override; production compiler limit unchanged, no shared cache eviction or persistent project settings write.'
	return prior

func flush_report()->void:
	audit.failures=failed;audit.passed=failed==0
	write_json(output_dir+"/editor_http.json",audit)

func run()->void:
	if '--syntax-only' in OS.get_cmdline_user_args():print('STREET_RECHECK syntax only');quit();return
	if DisplayServer.get_name()=='headless':push_error('Use the private desktop runner for HTTP/native texture validation');quit(2);return
	output_dir=DEST
	var prior:Dictionary={}
	if '--reuse-imports' in OS.get_cmdline_user_args() and FileAccess.file_exists(DEST+'/editor_http.json'):
		prior=JSON.parse_string(FileAccess.get_file_as_string(DEST+'/editor_http.json'))
	Engine.max_fps=60;rpc_timeout_ms=120000;root.size=Vector2i(1100,800)
	create_timer(1000).timeout.connect(func():audit.timeout=true;flush_report();quit(2))
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	check(data.assets.size()==11,'exact current eleven-asset manifest')
	prior=configure_isolated_content(prior)
	if failed>0:flush_report();quit(1);return
	var directory:=Paths.cache_directory('required_street_recheck_20261013_%d'%Time.get_ticks_usec())
	if prior.get('generator','')==Compile.generator() and Paths.allowed(str(prior.get('isolation_root','')),Paths.external_root()) and DirAccess.dir_exists_absolute(str(prior.get('isolation_root',''))+'/assets'):
		directory=prior.isolation_root
	DirAccess.make_dir_recursive_absolute(directory)
	var library:=Library.new(directory+'/assets')
	audit.merge({'manifest':MANIFEST,'isolation_root':directory,'generator':Compile.generator(),'engine':Engine.get_version_info(),'real_http':true})
	for item:Dictionary in data.assets:
		check(FileAccess.get_sha256(item.path)==item.sha256,'manifest exact current source '+item.id)
		var source_snapshot:String=Paths.external_root().path_join('sources').path_join(str(item.id)+'.glb')
		DirAccess.make_dir_recursive_absolute(source_snapshot.get_base_dir())
		if not FileAccess.file_exists(source_snapshot) or FileAccess.get_sha256(source_snapshot)!=item.sha256:
			check(DirAccess.copy_absolute(item.path,source_snapshot)==OK,'copy immutable source into isolated root '+item.id)
		check(FileAccess.get_sha256(source_snapshot)==item.sha256,'isolated source copy byte exact '+item.id)
		var row:Dictionary={}
		if prior.get('generator','')==Compile.generator():
			for previous:Dictionary in prior.get('items',[]):
				if previous.id!=item.id or previous.get('input_sha','')!=item.sha256 or not previous.get('passed',false):continue
				if not previous.get('semantic_exact',false) or previous.get('native_resource_stats',{}).is_empty():continue
				if FileAccess.get_sha256(previous.output_path)!=previous.output_sha:continue
				var product:Dictionary=Compile.read(previous.output_path)
				if product.get('hit',false):
					row=previous.duplicate(true);row.erase('http_passed');row.reused_identical_native=true
					check(true,'current identity validated; reuse exact imported semantics/native cost '+item.id)
				Drainer.dispose_result(product)
		if row.is_empty():row=import_item(library,item.id,source_snapshot)
		row.author_path=item.path;row.author_sha256=item.sha256;row.source_snapshot_path=source_snapshot
		check(FileAccess.get_sha256(item.path)==item.sha256,'original author source remains immutable '+item.id)
		audit.items.append(row);flush_report();await process_frame
	# Re-imported revisions intentionally have the same user-facing label.
	# The isolated retry catalogue can contain earlier candidates; bind this
	# test to the exact eleven current output identities and preserve its old
	# catalogue as evidence. Do not rename assets or weaken HTTP selection.
	var current_paths:Array=audit.items.filter(func(r):return r.has('output_path')).map(func(r):return str(r.output_path))
	var original_catalog:=directory+'/assets/library.json'
	var prior_catalog:=DEST+'/history/catalog_before_retry_%d.json'%Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(DEST+'/history')
	check(DirAccess.copy_absolute(original_catalog,prior_catalog)==OK,'preserve prior isolated catalogue')
	library=Library.new(directory+'/assets')
	library.entries=library.entries.filter(func(e):return str(e.get('asset_path','')) in current_paths)
	check(library.entries.size()==11,'exact current eleven output identities in isolated catalogue')
	check(library.save()==OK,'atomic current candidate catalogue fixture')
	var map_path:=directory+'/map_retry_%d.gltf'%Time.get_ticks_usec();var doc:=Doc.new();check(doc.save(map_path)==OK,'isolated empty map')
	var session=preload('res://scripts/net/net.gd').session();session.world3d_editor_path=map_path;session.world3d_editor_doc=null
	editor=preload('res://scripts/world_editor/world_editor.gd').new();editor._mcp_autostart=false;editor._draft_directory=directory+'/drafts';root.add_child(editor);await wait_loaded();editor._safety.enabled=false
	var probe:=TCPServer.new();port=29870
	while probe.listen(port,'127.0.0.1')!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,'isolated 3D HTTP start')
	await rpc('initialize',{'protocolVersion':'2025-03-26'})
	var names:Array=(await rpc('tools/list')).get('result',{}).get('tools',[]).map(func(t):return t.name)
	check(names.has('place_asset') and names.has('select_objects'),'current 3D tool discovery')
	for row:Dictionary in audit.items:
		if not row.has('entry'):continue
		# open_world intentionally clears an unbound library's in-memory entries.
		# Reload the isolated on-disk catalogue, not that emptied shared object.
		editor._assets=Library.new(directory+'/assets');editor._shared_assets=[]
		await http_item(row,map_path)
		check(row.get('editor_collision_bodies',0)>0,'native editor collision '+row.id)
		flush_report()
	audit.isolated_map=map_path
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_doc=null;session.world3d_editor_path=''
	root.get_node('AssetManager').content_root_override=original_content_override
	audit.completed=true;flush_report()
	print('STREET_RECHECK_HTTP failures=',failed);quit(0 if failed==0 else 1)
