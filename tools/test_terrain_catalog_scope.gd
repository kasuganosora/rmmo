extends "res://tools/test_world3d_mcp.gd"

class CountedLibrary:
	extends "res://scripts/world_editor/surface_material_library.gd"
	var reads:=0
	func entries(content_root:String="")->Array:
		reads+=1
		return super.entries(content_root)

func catalog_ready()->void:
	var deadline:=Time.get_ticks_msec()+30000
	while editor._material_panel._catalog_thread!=null and Time.get_ticks_msec()<deadline:await process_frame
	check(editor._material_panel._catalog_thread==null,"background material catalog finishes")

func has_option(field:OptionButton,id:String)->bool:
	for i in field.item_count:
		if str(field.get_item_metadata(i))==id:return true
	return false

func run()->void:
	Engine.max_fps=60
	var directory:=Paths.cache_directory("terrain_catalog_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var doc:=Doc.new()
	var id:String=doc.add_box("ground",Vector3.ZERO,Vector3(8,1,8))
	doc._find(id).terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-4.,"heights":[0.,0.,0.,0.,.1,0.,0.,0.,0.],"holes":[false,false,false,false]}
	var path:=directory.path_join("map.gltf");check(doc.save(path)==OK,"isolated terrain map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false
	await catalog_ready()
	var library:=CountedLibrary.new(directory.path_join("materials"));library.include_shared=false
	editor._material_tool.library=library;editor._material_panel.refresh();await catalog_ready()
	var panel=editor._terrain_panel
	var before:=var_to_bytes(doc.records);var history:=doc._undo.size()
	library.reads=0;panel.river_loaded="";panel.slope_loaded=""
	var started:=Time.get_ticks_usec();panel.refresh(id);var refresh_us:=Time.get_ticks_usec()-started
	check(library.reads==0,"terrain refresh uses published catalog without synchronous disk scan")
	check(has_option(panel.river_fields.fields.sand_material_id,"builtin:white") and has_option(panel.slope_fields.fields.rock_material_id,"builtin:checker"),"river and slope receive the complete shared catalog")
	check(before==var_to_bytes(doc.records) and history==doc._undo.size(),"catalog and form refresh do not mutate authoring or history")
	var city_panel=editor._city.panel
	var menus:Array=[city_panel.road_surface_panel.material_select]
	for child in [city_panel.waterway_panel,city_panel.bridge_panel,city_panel.fortification_panel]:menus.append_array(child.materials.values())
	check(menus.size()==11,"all eleven city material menus use the published catalog")
	var choices=preload("res://scripts/world_editor/material_choice.gd")
	for menu in menus:choices.choose(menu,"builtin:checker")
	panel.river_fields.fields.rock_end.value=3.75;panel.slope_fields.fields.steep_start.value=31.
	var river_before:Dictionary=panel.river_fields.values();var slope_before:Dictionary=panel.slope_fields.values()
	var image:=Image.create(2,2,false,Image.FORMAT_RGB8);image.fill(Color(.25,.5,.7));var png:=directory.path_join("soil.png");image.save_png(png)
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP starts")
	var imported:=await call_tool("import_surface_material",{"path":png,"name":"Catalog test soil"});await catalog_ready()
	check(has_option(panel.river_fields.fields.sand_material_id,imported.material_id) and has_option(panel.slope_fields.fields.rock_material_id,imported.material_id),"HTTP import publication updates both hidden terrain forms")
	var published_all:=true;var selected_all:=true
	for menu in menus:
		published_all=published_all and has_option(menu,imported.material_id)
		selected_all=selected_all and menu.get_item_metadata(menu.selected)=="builtin:checker"
	check(published_all and selected_all,"HTTP import updates eleven city menus without replacing pending choices")
	var catalog_panel=editor._material_panel;var full_catalog:Array=catalog_panel._entries
	catalog_panel._entries=[]
	var default_menu:=OptionButton.new();root.add_child(default_menu);choices.bind_menu(default_menu,catalog_panel,"Plain","builtin:checker")
	var explicit_menu:=OptionButton.new();root.add_child(explicit_menu);choices.bind_menu(explicit_menu,catalog_panel,"Plain","builtin:checker")
	explicit_menu.item_selected.emit(0)
	var authored_menu:=OptionButton.new();root.add_child(authored_menu);choices.bind_menu(authored_menu,catalog_panel,"Plain")
	var selection_events:=[0];authored_menu.item_selected.connect(func(_i):selection_events[0]+=1)
	choices.choose(authored_menu,imported.material_id)
	check(authored_menu.get_item_metadata(authored_menu.selected)==imported.material_id,"late authored choice is retained while catalog is empty")
	catalog_panel._entries=full_catalog;catalog_panel.catalog_changed.emit()
	check(default_menu.get_item_metadata(default_menu.selected)=="builtin:checker" and explicit_menu.get_item_metadata(explicit_menu.selected)=="","late initial default resolves but explicit plain selection stays plain")
	check(authored_menu.get_item_metadata(authored_menu.selected)==imported.material_id and not authored_menu.get_item_text(authored_menu.selected).begins_with("未找到"),"late catalog resolves authored material by identity")
	choices.choose(authored_menu,"missing:a");choices.choose(authored_menu,"missing:b");choices.choose(authored_menu,"builtin:checker")
	check(authored_menu.item_count==full_catalog.size()+1,"changing missing choices leaves no stale synthetic rows")
	choices.choose(authored_menu,imported.material_id)
	var loaded_absent:=OptionButton.new();root.add_child(loaded_absent);choices.bind_menu(loaded_absent,catalog_panel,"Plain","test:new")
	var later:Dictionary=full_catalog[0].duplicate(true);later.material_id="test:new"
	catalog_panel._entries=full_catalog+[later];catalog_panel.catalog_changed.emit()
	check(loaded_absent.get_item_metadata(loaded_absent.selected)=="","already loaded catalog consumes an unavailable preferred default only once")
	loaded_absent.free()
	catalog_panel._entries=full_catalog.filter(func(entry):return entry.material_id!=imported.material_id);catalog_panel.catalog_changed.emit()
	check(authored_menu.get_item_metadata(authored_menu.selected)==imported.material_id and authored_menu.get_item_text(authored_menu.selected).begins_with("未找到"),"removed material does not silently fall back to a different choice")
	check(selection_events[0]==0,"programmatic catalog rebuild emits no fake user selection")
	default_menu.free();explicit_menu.free();authored_menu.free()
	catalog_panel._entries=full_catalog;catalog_panel.catalog_changed.emit()
	check(before==var_to_bytes(doc.records) and history==doc._undo.size(),"city catalog publication and freed-menu callbacks do not edit authoring")
	check(equivalent(river_before,panel.river_fields.values()) and equivalent(slope_before,panel.slope_fields.values()),"new catalog preserves uncommitted numeric and material choices")
	editor._material_panel.refresh();await catalog_ready()
	check(equivalent(river_before,panel.river_fields.values()) and equivalent(slope_before,panel.slope_fields.values()),"repeated publication still preserves pending edits")
	var reload_started:=Time.get_ticks_usec();library.entries();library.entries();var duplicate_reads_us:=Time.get_ticks_usec()-reload_started
	print("TERRAIN_CATALOG_TIMINGS ",JSON.stringify({"refresh_ms":refresh_us/1000.,"two_catalog_reads_ms":duplicate_reads_us/1000.}))
	await call_tool("set_terrain_slope_materials",{"terrain_ids":[id],"rock_material_id":imported.material_id,"steep_start":28.,"steep_end":62.,"transition_width":0.})
	check(is_equal_approx(panel.slope_fields.fields.steep_start.value,28.),"document edit replaces pending form values with stored settings")
	# Simulate catalog still loading when a document with an authored material opens.
	var catalog: Array=editor._material_panel._entries
	editor._material_panel._entries=[];panel.slope_loaded="";panel.refresh(id)
	editor._material_panel._entries=catalog;panel._refresh_material_choices()
	check(panel.slope_fields.values().rock_material_id==imported.material_id,"late catalog resolves stored material instead of retaining a temporary fallback")
	await call_tool("undo");await call_tool("redo")
	check(is_equal_approx(panel.slope_fields.fields.steep_start.value,28.),"redo refreshes the same stored slope settings")
	var snapshot:=var_to_bytes(editor._doc.records)
	await call_tool("import_surface_material",{"path":directory.path_join("missing.png")},false)
	check(snapshot==var_to_bytes(editor._doc.records),"invalid import has no document side effects")
	await call_tool("save_world",{"path":path});await call_tool("open_world",{"path":path})
	check(is_equal_approx(editor._doc._find(id).terrain_slope_blend.steep_start,28.),"saved map reopens with its terrain material settings")
	editor.queue_free();await settle();print("TERRAIN_CATALOG_FAILED=",failed);quit(1 if failed else 0)
