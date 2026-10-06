extends SceneTree
const View=preload("res://scripts/char/character_view_3d.gd")
const Starter=preload("res://scripts/char/starter_equipment.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	var bg:=ColorRect.new();bg.color=Color("28343d");bg.size=Vector2(root.size);root.add_child(bg)
	for row in range(2):
		var gender:String="male" if row==0 else "female"
		for col in range(4):
			var origin:=Vector2(col*400,row*500)
			var title:=Label.new();title.text=("成年男性 · " if row==0 else "成年女性 · ")+["面部","素体正面","素体背面","初始装备"][col];title.position=origin+Vector2(20,14);root.add_child(title)
			var view:=View.new();view.portrait_mode=col==0;root.add_child(view);view.display.visible=false;view.viewport.size=Vector2i(512,640)
			view.configure(gender,{},Starter.PARTS if col in [0,3] else {})
			view.play("idle","back" if col==2 else "front",true);view.model.set_process(false);view.model.pose_at(0)
			var target_y:float=(1.74 if row==0 else 1.69) if col==0 else .96
			view.camera.size=.53 if col==0 else 2.1
			view.camera.position=Vector3(0,target_y+.10,5);view.camera.look_at(Vector3(0,target_y,0))
			var rect:=TextureRect.new();rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;rect.texture=view.viewport.get_texture();rect.position=origin+Vector2(14,48);rect.size=Vector2(360,450);root.add_child(rect)
	await create_timer(.4).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/refined_adults.png"))
	print("ADULT_REVIEW_OK");quit()
