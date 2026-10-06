extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1000,800)
	await process_frame
	var server=load("res://scripts/net/net.gd").server()
	server.inventory.clear();server.equipment.clear()
	for id:String in ["underwear_lace_bra_white","underwear_lace_briefs_white","traveler_shirt","traveler_trousers"]:
		server.inventory.add_item(id,1);assert(server.try_equip_item(id).ok)
	var hud=load("res://scenes/ui/game_hud.tscn").instantiate();root.add_child(hud)
	await process_frame
	hud._character={"name":"装备栏验收","gender":"female","class_id":"warrior","level":1}
	hud._toggle_window("character")
	for frame in 4:await process_frame
	var panel:Control=hud._windows.character
	var canvas:Control=panel.find_child("DollCanvas",true,false)
	assert(canvas!=null)
	var cells:Dictionary={}
	for child in canvas.get_children():
		if child.get_script()==preload("res://scripts/ui/equip_slot.gd"):
			cells[child.slot_id]=child
			assert(Rect2(Vector2.ZERO,canvas.size).encloses(child.get_rect()),"Equipment cell outside canvas")
			assert(panel.get_global_rect().encloses(child.get_global_rect()),"Equipment cell clipped by character window")
	assert(cells.has("underwear_top") and cells.has("underwear_bottom"))
	assert(cells.underwear_top.item_id=="underwear_lace_bra_white")
	assert(cells.underwear_bottom.item_id=="underwear_lace_briefs_white")
	for a:String in cells:
		for b:String in cells:
			if a!=b:assert(not cells[a].get_rect().intersects(cells[b].get_rect()),"Equipment cells overlap")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(Art.review_path("character_3d/underwear_equipment_panel.png"))
	# Use the real slot signal and production controller, not a test-only setter.
	cells.underwear_top.unequip_requested.emit("underwear_top")
	await process_frame
	assert(server.equipment.is_empty("underwear_top"))
	assert(server.equipment.get_item_in("underwear_bottom")=="underwear_lace_briefs_white")
	assert(server.inventory.get_qty("underwear_lace_bra_white")==1)
	var parts:Dictionary=preload("res://scripts/char/character_view_3d.gd").equipment_parts("female",server.equipment.snapshot(),server.item_catalog)
	var model=preload("res://scripts/char/character_model_3d.gd").create("female",{},parts);root.add_child(model)
	for mesh in model.gear.get("BaseTop",[]):assert(not mesh.visible)
	for mesh in model.gear.get("BaseBottom",[]):assert(mesh.visible)
	model.free();hud.free()
	print("PASS actual equipment panel, independent slot signal, inventory return and renderer visibility");quit()
