extends SceneTree
## Real HUD controls: an authoritative update must not destroy unrelated views.
## Headless measures update CPU work only; the full-game probe covers GPU frames.
class MapPlayer extends Node3D:
	var click_target:Variant=null
	var _route:Array=[]
class MapCombat extends RefCounted:
	var actors:Dictionary={}
class MapWorld extends Node:
	var _map_data=preload("res://scripts/world3d/world_map_data.gd").new()
	var _player:=MapPlayer.new()
	var _combat:=MapCombat.new()
	var _hud:Control
	var _ready_for_play:=true
var failures:Array=[]
var checks:=0
var measurements:Array=[]

func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL ",message)
func run()->void:
	root.get_node("GameSettings").persist_enabled=false
	ProjectSettings.set_setting("rmmo/characters_3d",false)
	var hud:Control=load("res://scenes/ui/game_hud.tscn").instantiate()
	root.add_child(hud)
	var world:=MapWorld.new();root.add_child(world);world.add_child(world._player);world._hud=hud
	world._map_data.bounds=Rect2(-100,-100,200,200)
	hud.bind_world_map_3d(world)
	hud.bind_character({"name":"Refresh fixture","class_id":"warrior","gender":"female","level":5})
	var initial_server:Node=root.get_node("MockServer")
	hud.apply_equipment_snapshot(initial_server.equipment.snapshot(),initial_server.equipment.total_bonuses())
	hud.apply_skill_catalog([{"id":"basic_attack","name":"Attack","type":"active","cooldown":5.}])
	hud.apply_skill_book({"known":["basic_attack"],"skill_points":1})
	for id:String in ["inventory","skills","quest","map","system","character"]:hud._toggle_window(id)
	await process_frame;await process_frame
	# Panning/zoom and a system option in progress must survive unrelated updates.
	hud._map_overview.center=Vector2(17,21);hud._map_overview.span=73.
	var actions:Dictionary={
		"inventory":func():hud.apply_inventory_snapshot([{"id":"potion_hp_small","qty":3}],120),
		"equipment":func():
			var server:Node=root.get_node("MockServer")
			server.inventory.grant_starter();check(server.try_equip_item("wooden_sword","weapon_main").ok,"fixture equips a real catalog item")
			# Normal inventory/hotbar actions may read the new gear first.
			hud._sync_equipment_cache()
			hud.apply_equipment_snapshot(server.equipment.snapshot(),server.equipment.total_bonuses()),
		"quest":func():hud.apply_quest_snapshot([{"id":"q1","title":"Test quest","status":"in_progress","objectives":[]}]),
		"catalog":func():hud.apply_skill_catalog([{"id":"basic_attack","name":"Updated attack","type":"active","cooldown":5.}]),
		"combat":func():hud.apply_combat_stats({"hp":77,"hp_max":180}),
		"cooldown":func():hud.note_skill_cooldown("basic_attack",4.,5.)}
	for key:String in actions:
		hud._map_overview.center=Vector2(17,21);hud._map_overview.span=73.
		var map_id:int=hud._map_overview.get_instance_id()
		var settings_ids:=child_ids(hud._windows.system.get_meta("body"))
		var skills_ids:=child_ids(hud._windows.skills.get_meta("body"))
		var character_ids:=child_ids(hud._windows.character.get_meta("body"))
		var bag_ids:=child_ids(hud._windows.inventory.get_meta("body"))
		var started:=Time.get_ticks_usec();actions[key].call()
		measurements.append({"action":key,"call_ms":(Time.get_ticks_usec()-started)/1000.})
		check(hud._map_overview.get_instance_id()==map_id,key+" preserves map and terrain cache")
		check(hud._map_overview.center==Vector2(17,21) and hud._map_overview.span==73.,key+" preserves map navigation")
		check(child_ids(hud._windows.system.get_meta("body"))==settings_ids,key+" preserves settings controls")
		if key in ["inventory","equipment","quest","combat","cooldown"]:
			check(child_ids(hud._windows.skills.get_meta("body"))==skills_ids,key+" preserves unrelated skill grid")
		if key=="equipment":
			check(child_ids(hud._windows.character.get_meta("body"))!=character_ids,"equipment change refreshes paperdoll")
			check(child_ids(hud._windows.inventory.get_meta("body"))!=bag_ids,"equipment change refreshes bag compare tips")
		if key=="combat":check(child_ids(hud._windows.character.get_meta("body"))==character_ids,"current HP change does not rebuild unchanged max-stat/paperdoll view")
		await process_frame;await process_frame
	check(hud._inventory_qty("potion_hp_small")==3,"inventory state updates")
	check(hud._server_gold==120,"wallet updates")
	check(hud._server_quests.size()==1,"journal updates")
	check(hud._hp==77.,"health updates")
	check(float(hud._skill_cd_hint.basic_attack.remaining)>0.,"cooldown remains active")
	var painted_cooldowns:=0
	for cell:Node in hud._skills_panel_logic._iter_skill_cells(hud._skills_panel_logic._skill_window_grid()):
		if hud._cell_bound_id(cell)=="basic_attack":
			painted_cooldowns+=1
			check(cell._cd!=null and cell._cd._cd_remaining>0.,"existing skill cell displays cooldown without rebuild")
	check(painted_cooldowns>0,"visible catalog contains the updated cooldown cell")
	var inventory_ids:=child_ids(hud._windows.inventory.get_meta("body"))
	hud.apply_inventory_snapshot(hud._server_inventory,121)
	check(child_ids(hud._windows.inventory.get_meta("body"))==inventory_ids,"wallet-only update preserves bag controls")
	check(hud._server_gold==121,"wallet-only update refreshes wallet")
	check(hud._windows.character.get_meta("gold_label").text.ends_with("121"),"wallet-only update refreshes open character gold in place")
	hud.apply_inventory_snapshot([],122)
	check(hud._server_inventory.is_empty(),"authoritative empty bag remains empty after rebuild")
	check(hud._server_gold==122,"bag rebuild preserves received wallet")
	var before:=Time.get_ticks_usec()
	for i in 20:
		hud.note_skill_cooldown("basic_attack",4.,5.)
	measurements.append({"action":"20_cooldown_updates","call_ms":(Time.get_ticks_usec()-before)/1000.})
	# Full session refresh is still supported, including multiple calls in one
	# frame; no deferred callback may keep a freed MapHost argument.
	hud.bind_character(hud._character);hud.bind_character(hud._character)
	await process_frame;await process_frame
	check(is_instance_valid(hud._map_overview),"explicit full rebind resolves current map host")
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var result:={"checks":checks,"failures":failures,"measurements":measurements,"scope":"headless real HUD update CPU; character appearance uses existing 2D fixture mode"}
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print(JSON.stringify(result))
	hud.queue_free();world.queue_free();await process_frame;await process_frame
	quit(0 if failures.is_empty() else 1)

func child_ids(node:Node)->Array:
	var result:Array=[]
	for child:Node in node.get_children():result.append(child.get_instance_id())
	return result
