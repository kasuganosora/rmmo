extends SceneTree
var failed:=0
func check(ok: bool,label: String):
	if not ok:failed+=1;push_error(label)
	else:print("PASS ",label)
func _init():call_deferred("run")
func run():
	var field=load("res://scripts/map/map_field.gd").new()
	field.skip_ready_rebuild=true;root.add_child(field);field.set_process(false)
	field.pack=load("res://scripts/map/tilemap_pack.gd").load_pack("user://content/packs/default","Axel256")
	field.collision=field.pack.collision;field.tile_size=field.pack.tile_size
	field.grid_width=field.pack.width;field.grid_height=field.pack.height
	var surface=field._surface_materials
	surface._load_channels()
	check(surface.is_scaled_prop_tile(32296) and surface.is_scaled_prop_tile(32299),"all lamp slices replaced")
	check(not surface.is_scaled_prop_tile(32278),"house window remains baked")
	var definition={}
	for light in field.pack.render_profile.lights:
		if light.get("kind")=="lamp":definition=light
	var chunk:=Node2D.new();field.add_child(chunk)
	var effects:=Node2D.new();effects.name="MaterialEffects";chunk.add_child(effects)
	var entries=[]
	for cell in [Vector2i(0,0),Vector2i(15,15)]:
		entries.append({"x":cell.x,"y":cell.y,"z":3,"definition":definition})
	surface._add_lights(chunk,0,0,16,16,entries)
	var sprites=[];var lights=[];var shadows=[]
	for node in effects.get_children():
		if node is Sprite2D:sprites.append(node)
		elif node is PointLight2D:lights.append(node)
		elif node is Line2D:shadows.append(node)
	check(sprites.size()==2,"one whole lamp per anchor including chunk corners")
	check(sprites[0].texture==sprites[1].texture,"lamps share GPU art texture")
	for i in range(2):
		var origin:=Vector2(entries[i].x,entries[i].y)*48
		check(sprites[i].position+Vector2(30,177)*sprites[i].scale==origin+Vector2(30,177),"ground contact preserved")
		check(sprites[i].scale==Vector2(1.5,1.5),"lamp enlarged uniformly")
		var expected: Vector2=sprites[i].position+Vector2(definition.offset[0],definition.offset[1])*1.5
		check(lights[i].position.is_equal_approx(expected),"light follows enlarged lantern")
		check(shadows[i].points[0]==origin+Vector2(30,177),"shadow begins at foot")
	surface._update_night(chunk,1.0)
	for sprite in sprites:check(sprite.material.get_shader_parameter("night_factor")==1.0,"all lamp emissions respond to night")
	check(sprites[0].position.y<0,"top crosses chunk boundary without being clipped")
	field.queue_free();await process_frame
	quit(1 if failed else 0)
