extends "res://tools/test_world3d_mcp.gd"
const Preferences=preload("res://scripts/world_editor/rendering_preferences.gd")

func external_change()->void:
	var config:=ConfigFile.new();config.load(Preferences.PATH)
	config.set_value("unrelated","preserved","external change");config.save(Preferences.PATH)

func saved()->void:
	var until:=Time.get_ticks_msec()+15000
	while editor._rendering_preferences.state().pending and Time.get_ticks_msec()<until:await process_frame
	var state:Dictionary=editor._rendering_preferences.state()
	check(not state.pending and state.last_result.get("ok",false),"background preference publication completed")

func run()->void:
	create_timer(120).timeout.connect(func():quit(2));rpc_timeout_ms=20000
	check(not FileAccess.file_exists(Preferences.PATH),"isolated user profile starts without rendering overrides")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=Doc.new();session.world3d_editor_path=""
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;root.add_child(editor);editor._safety.enabled=false
	await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start actual HTTP MCP")
	var listing:=await rpc("tools/list")
	var names:Array=[]
	for tool:Dictionary in listing.result.tools:names.append(tool.name)
	for name_:String in ["get_rendering_preferences","set_rendering_preferences","reset_rendering_preferences","restore_rendering_preferences"]:check(name_ in names,"tool discovery: "+name_)
	var before_records:Array=editor._doc.records.duplicate(true);var before_meta:Dictionary=editor._doc.map_meta.duplicate(true)
	var before_undo:int=editor._doc._undo.size();var dirty:bool=editor._dirty
	var initial:=await call_tool("get_rendering_preferences")
	check(initial.applied==Preferences.DEFAULTS and initial.saved==Preferences.DEFAULTS and not initial.restart_required,"startup and saved defaults agree")
	await call_tool("set_rendering_preferences",{"contact_shadows":"true"},false)
	await call_tool("set_rendering_preferences",{"unrelated_setting":true},false)
	await call_tool("set_rendering_preferences",{},false)
	check(not FileAccess.file_exists(Preferences.PATH),"invalid calls have no file side effect")
	await call_tool("restore_rendering_preferences",{},false)
	var existing:=ConfigFile.new();existing.set_value("unrelated","preserved","keep me");existing.save(Preferences.PATH)
	var pending:=await call_tool("set_rendering_preferences",{"contact_shadows":true,"multi_bounce_ao":true})
	check(pending.get("pending",false),"HTTP explicitly reports deferred persistence")
	await saved()
	var both:=await call_tool("get_rendering_preferences")
	check(both.saved=={"contact_shadows":true,"multi_bounce_ao":true} and both.applied==initial.applied and both.restart_required,"saved switches do not pretend to change the running renderer")
	existing.load(Preferences.PATH);check(existing.get_value("unrelated","preserved","")=="keep me","saving preserves unrelated existing config fields")
	check(not ProjectSettings.get_setting("rendering/"+Preferences.KEYS.contact_shadows) and not ProjectSettings.get_setting("rendering/"+Preferences.KEYS.multi_bounce_ao),"running project settings remain startup truth")
	var hash:=FileAccess.get_sha256(Preferences.PATH)
	await call_tool("set_rendering_preferences",{"multi_bounce_ao":7},false)
	check(FileAccess.get_sha256(Preferences.PATH)==hash,"invalid call preserves existing override bytes")
	var panel:AcceptDialog=editor._rendering_preferences_panel
	panel.refresh();panel.popup_centered();await settle()
	check(panel.visible and panel.choices.contact_shadows.button_pressed and panel.choices.multi_bounce_ao.button_pressed,"real preferences UI reflects HTTP settings")
	panel.choices.contact_shadows.button_pressed=false;panel._apply();await saved()
	check(editor._rendering_preferences.state().saved=={"contact_shadows":false,"multi_bounce_ao":true},"UI uses the same persistence operation")
	await call_tool("restore_rendering_preferences");await saved()
	check(editor._rendering_preferences.state().saved==both.saved,"restore previous recovers both switches")
	await call_tool("reset_rendering_preferences");await saved()
	check(editor._rendering_preferences.state().saved==Preferences.DEFAULTS and not editor._rendering_preferences.state().restart_required,"reset defaults cancels pending restart changes")
	await call_tool("restore_rendering_preferences");await saved()
	check(editor._rendering_preferences.state().saved==both.saved,"persistent previous state remains restorable")
	check(equivalent(editor._doc.records,before_records) and equivalent(editor._doc.map_meta,before_meta) and editor._doc._undo.size()==before_undo and editor._dirty==dirty,"machine preferences do not modify map, dirty state or map history")
	check(editor._rendering_preferences._queue.ledger==editor._shared_preparation_ledger and editor._rendering_preferences._queue.snapshot().inflight_current==0,"shared queue releases its completed work")
	var worker:=Thread.new()
	check(worker.start(Preferences._write.bind(Preferences.DEFAULTS,both.saved,FileAccess.get_sha256(Preferences.PATH),external_change))==OK,"start deterministic commit conflict fixture")
	while worker.is_alive():await process_frame
	var conflict:Dictionary=worker.wait_to_finish()
	existing.load(Preferences.PATH)
	check(not conflict.ok and existing.get_value("unrelated","preserved","")=="external change" and editor._rendering_preferences.state().saved==both.saved,"change after staging rejects publication and preserves external edits")
	print("RENDERING_PREFERENCES_RESULT ",JSON.stringify(editor._rendering_preferences.state()))
	panel.hide();editor.queue_free();await settle();session.world3d_editor_doc=null;session.world3d_editor_path=""
	print("RENDERING_PREFERENCES_FAILED=",failed);quit(1 if failed else 0)
