extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
const Weather=preload("res://scripts/map/weather.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	for gender in ["female","male"]:
		for id in range(10,16):
			var model:=Model.new();root.add_child(model);model.set_process(false)
			model.configure(gender,{"part_ids":{"FrontHair1":id}},{"Clothing1":3,"Boots":2,"HeadAccessory":1})
			assert(model.skeleton.get_bone_count()==70)
			var visible:=0
			for mesh in model.gear.Hair:
				if mesh.visible:
					assert(str(mesh.name).begins_with("Hair_"+str(id)+"_"));assert(mesh.skin!=null);visible+=1
					if id in [10,12,14,15]:
						var uv2:PackedVector2Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
						assert(not uv2.is_empty(),"Layered hair gradient coordinates must survive export on both bodies")
			assert(visible>10)
			var motion=model.imported_rig.hair_motion
			model.environment_wind=Vector2.RIGHT
			for frame in range(180):model._process(1.0/60)
			assert(motion.angles[2].length()>.1,"Idle hair must respond to wind")
			model.environment_wind=Vector2.ZERO
			for frame in range(240):model._process(1.0/60)
			assert(motion.angles[2].length()<.002,"Hair settles after wind stops")
			model.play("dash","back",true)
			for frame in range(30):model._process(1.0/60)
			assert(motion.angles[2].length()>.005,"Running moves hair")
			model.free()
	var storm:=Weather.compose(0,"storm",1,false)
	assert(Weather.sample_wind(storm,1).length()>.5)
	assert(Weather.sample_wind(Weather.compose(0,"storm",1,true),1)==Vector2.ZERO)
	assert(Weather.wind_vector(Weather.blend({"wind":Vector2.RIGHT},{"wind":Vector2.LEFT},.5)).length()<.001)
	var fx=preload("res://scripts/map/weather_fx.gd").new();root.add_child(fx);fx.apply(storm)
	var world_view=preload("res://scripts/char/character_view_3d.gd").new();root.add_child(world_view)
	world_view.driver=AnimatedSprite2D.new();root.add_child(world_view.driver)
	world_view._process(0.016)
	assert(world_view.model.environment_wind.length()>.5,"Map actors receive active weather")
	world_view.driver.free();world_view.driver=null;world_view._process(0.016)
	assert(world_view.model.environment_wind==Vector2.ZERO,"Preview is isolated from outdoor weather")
	world_view.free();fx.free()
	var creator=load("res://scenes/character_create.tscn").instantiate();root.add_child(creator)
	await process_frame;await process_frame
	var selector:OptionButton=creator.find_child("HairstyleSelect",true,false)
	assert(selector!=null and selector.item_count==8)
	selector.select(selector.get_item_index(14));selector.item_selected.emit(selector.selected)
	await process_frame;await process_frame
	assert(creator._view_3d.model.appearance.part_ids.FrontHair1==14)
	var saved:=Customization.from_dict(JSON.parse_string(JSON.stringify(creator._custom.to_dict())))
	assert(saved.part_ids.FrontHair1==14)
	print("PASS six hairstyles on both bodies, shared equipment, wind at rest, settling, running, indoor calm, transition and UI save")
	quit()
