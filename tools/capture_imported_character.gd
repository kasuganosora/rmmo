extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Starter=preload("res://scripts/char/starter_equipment.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var gender:="male" if "--male" in OS.get_cmdline_user_args() else "female"
	root.size=Vector2i(1440,960)
	root.content_scale_size=Vector2i(1440,960)
	var bg:=ColorRect.new();bg.color=Color("28343d");bg.size=Vector2(1440,960);root.add_child(bg)
	var cases:=[
		["面部近景","idle","front",true,true], ["初始装备","idle","front",false,true],
		["卸下外装 · 正面","idle","front",false,false],["卸下外装 · 背面","idle","back",false,false],
		["走动","walk","front_left",false,true],["施法","cast","front",false,true],
		["坐在地上","sit_ground","front",false,true],["坐在椅子上","sit_chair","left",false,true]]
	for i in range(cases.size()):
		var item:Array=cases[i]
		var view:=View.new();view.portrait_mode=item[3];root.add_child(view);view.display.visible=false
		view.viewport.size=Vector2i(512,640)
		view.configure(gender,{},Starter.PARTS if item[4] else {})
		view.play(item[1],item[2],true);view.model.set_process(false);view.model.pose_at(.35)
		if item[3]:
			view.camera.size=.47;view.camera.position=Vector3(0,1.7,4);view.camera.look_at(Vector3(0,1.71,0))
		else:
			var target_y:float=.5 if item[1] in ["sit_ground","sit_chair"] else .95
			view.camera.size=2.05;view.camera.position=Vector3(0,target_y+.3,5);view.camera.look_at(Vector3(0,target_y,0))
		var origin:=Vector2((i%4)*360,(i/4)*480)
		var label:=Label.new();label.text=item[0];label.position=origin+Vector2(28,12);root.add_child(label)
		var rect:=TextureRect.new();rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.texture=view.viewport.get_texture();rect.position=origin+Vector2(12,45);rect.size=Vector2(336,420);root.add_child(rect)
	await create_timer(.3).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/imported_review_")+gender+".png")
	print("IMPORTED_REVIEW_OK");quit()
