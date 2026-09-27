extends Node3D
## Controlled review scene, inspired by the two user-provided Fab references.
## The source artists did not publish their Marmoset lights/exposure settings.
const Model=preload("res://scripts/char/character_model_3d.gd")
@export var interactive:=true
var model:Node3D
var camera:Camera3D
var environment:Environment
var lighting:Node3D
var key:DirectionalLight3D
var fill:DirectionalLight3D
var rim:DirectionalLight3D
var gender:="female"
var outfit:Dictionary={}
var turn:=0.0
var studio_mode:=true
var regional_preview:Node3D
var outfit_buttons:Array[Button]=[]
var status_label:Label
var previous_msaa:int
var body_pose_controls:HBoxContainer
var pose_selector:OptionButton
var pose_amount:HSlider
var pose_play:CheckBox
var pose_clock:=0.0
var chair:Node3D
var floor_mesh:MeshInstance3D
var surface_wardrobe:Node3D
var garment_selector:OptionButton
var cloth_toggle:CheckBox
var cloth_clock:=0.0
const GARMENT_LOOKS=[
	["不穿外装",{}],
	["女仆 · 连衣裙",{"Clothing1":"maid_classic/item_00"}],
	["女仆 · 分体",{"Clothing1":"maid_separate/item_02","Clothing2":"maid_separate/item_01","HeadAccessory":"maid_separate/item_00"}],
	["百褶裙",{"Clothing2":"skirt_pleated/item_00"}],
	["包臀裙",{"Clothing2":"skirt_pencil/item_00"}],
	["多层礼裙 L",{"Clothing1":"dress_long/item_00","HeadAccessory":"dress_long/item_02"}],
	["拖地长裙",{"Clothing1":"dress_elf/item_00"}],
	["分层裙 M08",{"Clothing1":"dress_layered/item_00"}],
	["复杂叠裙 HW",{"Clothing1":"dress_ruffle_layers/item_00","Clothing2":"dress_ruffle_layers/item_01","HeadAccessory":"dress_ruffle_layers/item_02"}]]
func set_surface_outfit(index:int)->void:
	if regional_preview==null:return
	if surface_wardrobe==null:
		surface_wardrobe=preload("res://scripts/char/character_surface_wardrobe.gd").new()
		regional_preview.add_child(surface_wardrobe);surface_wardrobe.configure(regional_preview)
	if not surface_wardrobe.set_equipment(GARMENT_LOOKS[index][1]):push_error("Cannot equip surface garment");return
	if cloth_toggle and cloth_toggle.button_pressed:set_cloth_preview(true)
	if status_label:status_label.text="新素体换装检查 · 表面绑定已接入；裙摆物理/碰撞尚未验收"
func set_cloth_preview(enabled:bool)->void:
	if surface_wardrobe==null:return
	if enabled:
		if not surface_wardrobe.warm_start_cloth():push_error("Cloth preview unavailable")
		return
	for garment:Node3D in surface_wardrobe.garments.values():
		garment.disable_cloth()
func reset_cloth_preview()->void:
	if surface_wardrobe==null:return
	for garment:Node3D in surface_wardrobe.garments.values():
		garment.disable_cloth()
	if cloth_toggle and cloth_toggle.button_pressed:set_cloth_preview(true)
func show_new_base()->void:
	if regional_preview==null:
		regional_preview=preload("res://scripts/char/female_axis_body.gd").new()
		add_child(regional_preview)
		regional_preview.initialize();regional_preview.enable_compute();regional_preview.set_test_pose("stand")
	regional_preview.visible=true;regional_preview.rotation.y=turn;model.visible=false
	regional_preview.set_test_pose("stand")
	if pose_selector:pose_selector.select(0);pose_amount.set_value_no_signal(1);pose_play.button_pressed=false
	camera.size=2.5;camera.position=Vector3(0,1.05,5);camera.look_at(Vector3(0,1.05,0))
	for button in outfit_buttons:button.disabled=true
	if status_label:status_label.text="新素体换装检查 · 表面绑定已接入；裙摆物理/碰撞尚未验收"
	if garment_selector:garment_selector.visible=true
	if cloth_toggle:cloth_toggle.get_parent().visible=true
	if body_pose_controls:body_pose_controls.visible=true
	update_pose_helpers()
func rotate_body()->void:
	turn+=PI/4;model.rotation.y=turn
	if regional_preview:regional_preview.rotation.y=turn
	if chair:chair.rotation.y=turn
func add_light(angles:Vector3,energy:float,color:Color)->DirectionalLight3D:
	var result:=DirectionalLight3D.new();result.rotation_degrees=angles;result.light_energy=energy;result.light_color=color
	result.shadow_enabled=true;result.light_angular_distance=3.0
	# Review subjects are under two metres; distant cascades waste precision and
	# produce shadow acne on bent limbs and the chair.
	result.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	result.directional_shadow_max_distance=8.0
	result.shadow_bias=.15;result.shadow_normal_bias=1.0
	lighting.add_child(result);return result
func _ready()->void:
	# Close-up material review uses geometric MSAA without temporal blur/ghosting.
	previous_msaa=get_viewport().msaa_3d
	get_viewport().msaa_3d=Viewport.MSAA_8X
	var world:=WorldEnvironment.new();environment=Environment.new();world.environment=environment;add_child(world)
	environment.background_mode=Environment.BG_COLOR;environment.background_color=Color("19191c")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("eee9e6");environment.ambient_light_energy=.25
	lighting=Node3D.new();add_child(lighting)
	key=add_light(Vector3(-32,-32,0),1.0,Color("fffdfb"))
	fill=add_light(Vector3(-12,48,0),.30,Color("e9efff"))
	rim=add_light(Vector3(-25,145,0),.8,Color("fff8f1"))
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.45;add_child(camera)
	camera.position=Vector3(0,1.35,5);camera.look_at(Vector3(0,1.35,0))
	model=Model.create(gender,{},{});add_child(model);model.set_process(false);model.play("idle","front",true);model.pose_at(0)
	if interactive:
		controls();show_new_base()
func _exit_tree()->void:
	get_viewport().msaa_3d=previous_msaa
func configure_body(value:String)->void:
	if garment_selector:garment_selector.visible=false
	if cloth_toggle:cloth_toggle.get_parent().visible=false
	if regional_preview:regional_preview.visible=false
	if body_pose_controls:body_pose_controls.visible=false
	if chair:chair.visible=false
	if floor_mesh:floor_mesh.visible=false
	model.visible=true
	camera.size=1.45;camera.position.y=1.35
	for button in outfit_buttons:button.disabled=false
	if status_label:status_label.text="原角色对照 · 共享角色与装备系统"
	gender=value;model.configure(gender,{},outfit);model.play("idle","front",true);model.pose_at(0);model.rotation.y=turn
func set_outfit(value:Dictionary)->void:
	outfit=value;model.set_equipment(outfit);model.pose_at(0)
func toggle_lighting()->void:
	studio_mode=not studio_mode;lighting.rotation=Vector3.ZERO
	fill.visible=studio_mode;rim.visible=studio_mode
	key.rotation_degrees=Vector3(-32,-32,0) if studio_mode else Vector3(-48,32,0)
	key.light_energy=1.0 if studio_mode else 1.15
	key.light_color=Color("fffdfb") if studio_mode else Color.WHITE
	environment.background_color=Color("19191c") if studio_mode else Color("899ba6")
	environment.ambient_light_color=Color("eee9e6") if studio_mode else Color("b8c2d1")
	environment.ambient_light_energy=.25 if studio_mode else .42
func controls()->void:
	var canvas:=CanvasLayer.new();add_child(canvas)
	var box:=VBoxContainer.new();box.position=Vector2(12,12);canvas.add_child(box)
	var title:=Label.new();title.text="皮肤验收 · 参考棚拍 / 游戏光照";box.add_child(title)
	var info:=Label.new();info.text="固定曝光；棚拍灯光按参考图推定，非原作者参数。";box.add_child(info)
	status_label=Label.new();box.add_child(status_label)
	var row:=HBoxContainer.new();box.add_child(row)
	for entry in [["新素体 · 瓷白",show_new_base],["旧女性对照",func():configure_body("female")],["旧男性对照",func():configure_body("male")],["转身 45°",rotate_body],["转灯 45°",func():lighting.rotation.y+=PI/4],["棚拍 / 游戏",toggle_lighting]]:
		var button:=Button.new();button.text=entry[0];button.pressed.connect(entry[1]);row.add_child(button)
	var outfits:=HBoxContainer.new();box.add_child(outfits)
	for entry in [["基础层",func():set_outfit({})],["初始装备",func():set_outfit(preload("res://scripts/char/starter_equipment.gd").PARTS)],["裙装",func():set_outfit({"Clothing1":2,"Boots":2,"HeadAccessory":1})],["全身 / 近景",func():camera.size=2.3 if camera.size<2 else 1.45;camera.position.y=1.0 if camera.size>2 else 1.35]]:
		var button:=Button.new();button.text=entry[0];button.pressed.connect(entry[1]);outfits.add_child(button)
		if entry[0]!="全身 / 近景":outfit_buttons.append(button)
	body_pose_controls=HBoxContainer.new();box.add_child(body_pose_controls)
	pose_selector=OptionButton.new();body_pose_controls.add_child(pose_selector)
	for entry in [["自然站立","stand"],["屈肘","elbow"],["抬臂","reach"],["抬腿","step"],["坐下 · 白模椅","sit"],["躺下","lie"],["原始 T 姿","rest"]]:
		pose_selector.add_item(entry[0]);pose_selector.set_item_metadata(pose_selector.item_count-1,entry[1])
	pose_amount=HSlider.new();pose_amount.min_value=0;pose_amount.max_value=1;pose_amount.step=.01;pose_amount.value=1;pose_amount.custom_minimum_size.x=140;body_pose_controls.add_child(pose_amount)
	pose_play=CheckBox.new();pose_play.text="循环检查";body_pose_controls.add_child(pose_play)
	pose_selector.item_selected.connect(func(_index):pose_amount.set_value_no_signal(1);apply_body_pose())
	pose_amount.value_changed.connect(func(_value):apply_body_pose())
	garment_selector=OptionButton.new();box.add_child(garment_selector)
	for entry:Array in GARMENT_LOOKS:garment_selector.add_item(entry[0])
	garment_selector.item_selected.connect(set_surface_outfit)
	var cloth_row:=HBoxContainer.new();box.add_child(cloth_row)
	cloth_toggle=CheckBox.new();cloth_toggle.text="布料实验 · 未验收";cloth_row.add_child(cloth_toggle)
	cloth_toggle.toggled.connect(set_cloth_preview)
	var reset:=Button.new();reset.text="重置布料";reset.pressed.connect(reset_cloth_preview);cloth_row.add_child(reset)
func apply_body_pose()->void:
	if regional_preview==null or not regional_preview.visible:return
	regional_preview.set_test_pose(pose_selector.get_item_metadata(pose_selector.selected),pose_amount.value)
	camera.size=2.5;camera.position=Vector3(0,1.05,5);camera.look_at(Vector3(0,1.05,0))
	if regional_preview.pose_name=="lie":camera.size=3.3;camera.position=Vector3(4,1.2,.3);camera.look_at(Vector3(0,.2,.16))
	update_pose_helpers()
func _process(delta:float)->void:
	if pose_play and pose_play.button_pressed and regional_preview and regional_preview.visible:
		pose_clock+=delta;pose_amount.set_value_no_signal(.5-.5*cos(pose_clock*1.5));apply_body_pose()
	if cloth_toggle and cloth_toggle.button_pressed and regional_preview and regional_preview.visible and surface_wardrobe:
		cloth_clock+=minf(delta,1.0/30.0)
		if cloth_clock>=1.0/60.0:
			cloth_clock=fmod(cloth_clock,1.0/60.0)
			surface_wardrobe.step_cloth()
func add_white_box(parent:Node3D,size:Vector3,position_value:Vector3)->void:
	var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=size;mesh.mesh=box;mesh.position=position_value
	var material:=StandardMaterial3D.new();material.albedo_color=Color("b9bdc3");material.roughness=.8;mesh.material_override=material;parent.add_child(mesh)
var seat_contact_clearance:=.006
func update_pose_helpers()->void:
	if chair:chair.free();chair=null
	if floor_mesh==null:
		floor_mesh=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(6,6);floor_mesh.mesh=plane
		var material:=StandardMaterial3D.new();material.albedo_color=Color("50555b");material.roughness=.9;floor_mesh.material_override=material;add_child(floor_mesh)
	floor_mesh.visible=regional_preview!=null and regional_preview.visible
	if regional_preview==null or regional_preview.pose_name!="sit":return
	if pose_amount and pose_amount.value<.99:return
	var local_hip:Vector3=regional_preview.skeleton.get_bone_global_pose(regional_preview.skeleton.find_bone("hip")).origin+regional_preview.root_offset
	var hip:Vector3=local_hip+regional_preview.world_offset
	# Use the final CPU surface snapshot; a helper rebuilt just after posing
	# must not depend on when an asynchronous GPU readback becomes visible.
	var points:PackedVector3Array=regional_preview.posed_points
	var seat_y:=hip.y
	for point:Vector3 in points:
		point+=regional_preview.root_offset
		# The whole seat footprint includes the forward underside of the hips.
		# Sampling only z<0 put the seat through 8.6 mm of the sitting body.
		if absf(point.x)<.23 and absf(point.z)<.22 and point.y>local_hip.y-.25 and point.y<local_hip.y+.1:
			seat_y=minf(seat_y,point.y+regional_preview.world_offset.y-seat_contact_clearance)
	seat_y=maxf(.2,seat_y)
	chair=Node3D.new();add_child(chair);chair.rotation.y=turn
	add_white_box(chair,Vector3(.46,.04,.44),Vector3(0,seat_y-.02,0))
	for x in [-.19,.19]:
		for z in [-.17,.17]:add_white_box(chair,Vector3(.035,seat_y-.04,.035),Vector3(x,(seat_y-.04)*.5,z))
	add_white_box(chair,Vector3(.46,.48,.035),Vector3(0,seat_y+.24,-.22))
