extends Node
## A disposable editor actor. Shares the live picking shapes, with a separate
## physical mask, and never enters WorldDocument, navigation baking or saves.
const Schema=preload("res://scripts/world_editor/mcp_schema.gd")
const WALK_MASK:=1<<20
const HEIGHT:=1.8
const RADIUS:=.3
const HINT:="胶囊行走 · WASD 移动 · Shift 加速 · 空格跳跃 · 右键转向 · 滚轮远近 · 左键编辑 · F6 / Esc 退出"
var editor:Node3D
var active:=false
var body:CharacterBody3D
var capsule:CapsuleShape3D
var visual:MeshInstance3D
var keys:Dictionary={}
var looking:=false
var viewport_focused:=true
var yaw:=0.
var pitch:=-20.
var distance:=4.5
var _saved:Dictionary={}
var _document:RefCounted
var _safe:=Vector3.ZERO
var _jump:=false
var _motion:=Vector2.ZERO
var _seconds:=0.
var _fast:=false
var _camera_shape:SphereShape3D

func _ready()->void:set_physics_process(false)

static func physical(extras:Dictionary)->bool:
	return extras.get("rmmo_collision","")!="none" and not extras.get("hostile",false) and not extras.get("ally",false)

func state()->Dictionary:
	return {"active":active,"perspective":"third_person","position":_xyz(body.position) if active else [],"height":HEIGHT,"radius":RADIUS,"yaw":yaw,"pitch":pitch,"distance":distance,"motion_remaining":_seconds,"grounded":body.is_on_floor() if active else false}

static func _xyz(v:Vector3)->Array:return [v.x,v.y,v.z]
static func _error(message:String)->Dictionary:return {"ok":false,"error":message}

func set_enabled(args:Dictionary)->Dictionary:
	var invalid:=Schema.validate(args,Schema.spec("", "",{"enabled":{"type":"boolean"},"position":Schema.vector(3,-100000,100000)},["enabled"]).inputSchema)
	if not invalid.is_empty():return _error(invalid)
	if not args.enabled and args.has("position"):return _error("退出行走不能同时设置位置")
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	if not args.enabled:
		stop();return {"ok":true,"walk":state()}
	if active and not args.has("position"):return {"ok":true,"walk":state()}
	var target:Vector3=Vector3.INF
	if args.has("position"):
		var requested:=Vector3(args.position[0],args.position[1],args.position[2])
		target=_ground(requested,.25,.35)
	else:target=_entry_point()
	if not target.is_finite():return _error("附近没有可站立的地面或胶囊空间不足；请对准空旷地面再进入")
	if not active:
		var camera:Camera3D=editor._camera
		_saved={"transform":camera.transform,"projection":camera.projection,"size":camera.size,"near":camera.near,"far":camera.far,"fov":camera.fov,"keep_aspect":camera.keep_aspect,"center":editor._orbit_center,"angles":editor._city._angles,"distance":editor._city._distance,"canvas_hint":editor._canvas.tooltip_text}
		_document=editor._doc
		yaw=wrapf(camera.rotation_degrees.y,-180,180);pitch=-20.;distance=4.5
		body=CharacterBody3D.new();body.name="EditorWalkCapsule"
		body.collision_layer=0;body.collision_mask=WALK_MASK
		body.floor_snap_length=.35;body.floor_max_angle=deg_to_rad(45);body.safe_margin=.003
		capsule=_shape()
		var collider:=CollisionShape3D.new();collider.shape=capsule;collider.position.y=HEIGHT*.5;body.add_child(collider)
		visual=MeshInstance3D.new();visual.name="CapsuleGuide"
		var mesh:=CapsuleMesh.new();mesh.radius=RADIUS;mesh.height=HEIGHT;mesh.radial_segments=20;mesh.rings=8
		visual.mesh=mesh;visual.position.y=HEIGHT*.5
		var material:=StandardMaterial3D.new();material.albedo_color=Color("45bac5");material.roughness=.7
		visual.material_override=material;body.add_child(visual);add_child(body)
		_camera_shape=SphereShape3D.new();_camera_shape.radius=.16
		camera.projection=Camera3D.PROJECTION_PERSPECTIVE;camera.near=.05
		editor._canvas.tooltip_text=HINT
		active=true;editor._camera_navigation.reset();set_physics_process(true)
	reset_input();viewport_focused=true
	body.position=target;body.velocity=Vector3.ZERO;body.force_update_transform();_safe=target
	_update_camera();_sync_ui()
	return {"ok":true,"walk":state()}

func stop()->void:
	if not active:return
	active=false;set_physics_process(false);reset_input()
	if is_instance_valid(body):body.free()
	body=null;visual=null;capsule=null;_camera_shape=null;_document=null
	var camera:Camera3D=editor._camera
	for key in ["transform","projection","size","near","far","fov","keep_aspect"]:camera.set(key,_saved[key])
	editor._orbit_center=_saved.center;editor._city._angles=_saved.angles;editor._city._distance=_saved.distance
	editor._canvas.tooltip_text=_saved.canvas_hint
	_saved.clear();editor._city.update_grid();_sync_ui()

func _sync_ui()->void:
	if editor._walk_button!=null:editor._walk_button.set_pressed_no_signal(active)
	# W belongs to walking here; the toolbar remains available for move mode.
	if not editor._transform_buttons.is_empty():editor._transform_buttons[0].text="移动" if active else "移动 W"
	if editor._city.overlay!=null:editor._city.overlay.refresh()
	if editor._status!=null:editor._status.text=editor._hint()

func reset_input()->void:
	keys.clear();looking=false;_jump=false;_motion=Vector2.ZERO;_seconds=0.;_fast=false

func _typing()->bool:
	var focus=editor.get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit

func input(event:InputEvent)->bool:
	if not active:return false
	if event is InputEventKey:
		var key:int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if not event.pressed:keys.erase(key)
		if _typing():reset_input();return false
		if event.pressed and key==KEY_ESCAPE and editor._gameplay.guard().ok:stop();return true
		if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:return false
		if key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT,KEY_SPACE] and viewport_focused:
			if event.pressed and not event.echo:
				keys[key]=true;_seconds=0.
				if key==KEY_SPACE:_jump=true
			return true
	if event is InputEventMouseButton:
		var inside:bool=editor._canvas.get_global_rect().has_point(event.position)
		if event.pressed:
			viewport_focused=inside
			if not inside:reset_input();return false
			var focus=editor.get_viewport().gui_get_focus_owner()
			if focus!=null:focus.release_focus()
		if event.button_index==MOUSE_BUTTON_RIGHT:
			if not event.pressed:
				var used:=looking
				looking=false
				return used
			if inside and editor._gameplay.guard().ok:looking=true;return true
		if inside and event.button_index==MOUSE_BUTTON_MIDDLE:return true
		if inside and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			set_view({"distance":clampf(distance*(.85 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.18),1.5,12.)});return true
	if event is InputEventMouseMotion:
		if looking:
			set_view({"yaw":wrapf(yaw-event.relative.x*.28,-180,180),"pitch":clampf(pitch-event.relative.y*.28,-75,55)});return true
		if event.button_mask&MOUSE_BUTTON_MASK_MIDDLE:return true
	return false

func set_view(args:Dictionary)->Dictionary:
	var invalid:=Schema.validate(args,Schema.spec("","",{"yaw":Schema.number(-360,360),"pitch":Schema.number(-75,55),"distance":Schema.number(1.5,12)}).inputSchema)
	if not invalid.is_empty():return _error(invalid)
	if not active:return _error("请先进入胶囊行走模式")
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	yaw=wrapf(float(args.get("yaw",yaw)),-180,180);pitch=float(args.get("pitch",pitch));distance=float(args.get("distance",distance))
	_update_camera();return {"ok":true,"walk":state()}

func move(args:Dictionary)->Dictionary:
	var invalid:=Schema.validate(args,Schema.spec("","",{"direction":Schema.vector(2,-1,1),"duration":Schema.number(.01,2),"fast":{"type":"boolean"},"jump":{"type":"boolean"}},["direction","duration"]).inputSchema)
	if not invalid.is_empty():return _error(invalid)
	if not active:return _error("请先进入胶囊行走模式")
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	reset_input();_motion=Vector2(args.direction[0],args.direction[1]).limit_length();_seconds=args.duration;_fast=args.get("fast",false);_jump=args.get("jump",false)
	return {"ok":true,"walk":state()}

static func _shape()->CapsuleShape3D:
	var shape:=CapsuleShape3D.new();shape.height=HEIGHT;shape.radius=RADIUS;return shape

func _clear(feet:Vector3)->bool:
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=_shape();query.collision_mask=WALK_MASK
	query.transform=Transform3D(Basis.IDENTITY,feet+Vector3.UP*(HEIGHT*.5));query.margin=.005
	return editor.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _ground(point:Vector3,above:float,below:float)->Vector3:
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*above,point-Vector3.UP*below,WALK_MASK)
	var hit:Dictionary=editor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y<cos(deg_to_rad(45)):return Vector3.INF
	var feet:Vector3=hit.position+Vector3.UP*.025
	return feet if _clear(feet) else Vector3.INF

func _entry_point()->Vector3:
	var camera:Camera3D=editor._camera
	var screen:Vector2=editor._canvas.size*.5
	var origin:=camera.project_ray_origin(screen)
	var hit:Dictionary=editor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*camera.far,WALK_MASK))
	var centers:Array[Vector3]=[editor._orbit_center,Vector3(editor._authoring.settings.spawn[0],editor._authoring.settings.spawn[1],editor._authoring.settings.spawn[2])]
	if not hit.is_empty():centers.push_front(hit.position)
	for center in centers:
		for offset in [Vector3.ZERO,Vector3(1,0,0),Vector3(-1,0,0),Vector3(0,0,1),Vector3(0,0,-1)]:
			var feet:=_ground(center+offset,.3,20.)
			if feet.is_finite():return feet
	return Vector3.INF

func _physics_process(delta:float)->void:
	if not active:return
	if editor._doc!=_document:stop();return
	if editor.saving() or _typing() or not editor._gameplay.guard().ok:
		reset_input();body.velocity=Vector3.ZERO;return
	var direction:=_motion if _seconds>0 else Vector2(int(keys.has(KEY_D))-int(keys.has(KEY_A)),int(keys.has(KEY_W))-int(keys.has(KEY_S))).limit_length()
	var speed:=7. if (_fast if _seconds>0 else keys.has(KEY_SHIFT)) else 3.5
	# A queued MCP command ends at the same physical update as keyboard motion.
	var fraction:=minf(1.,_seconds/maxf(delta,.0001)) if _seconds>0 else 1.
	_seconds=maxf(0.,_seconds-delta)
	var basis:=Basis(Vector3.UP,deg_to_rad(yaw))
	var wish:Vector3=(basis.x*direction.x-basis.z*direction.y)*speed*fraction
	body.velocity.x=wish.x;body.velocity.z=wish.z
	if _jump and body.is_on_floor():body.velocity.y=5.
	_jump=false
	if not body.is_on_floor():body.velocity.y=maxf(-35.,body.velocity.y-18.*delta)
	elif body.velocity.y<0:body.velocity.y=0
	if body.velocity.y<=0 and body.is_on_floor() and not wish.is_zero_approx() and body.test_move(body.global_transform,wish*delta):_step_up(wish,delta)
	body.move_and_slide()
	if body.is_on_floor():_safe=body.position
	if body.position.y<_safe.y-30.:
		var ground:=_ground(_safe,.3,1.)
		if not ground.is_finite():stop();editor._status.text="脚下地面已移除，已退出胶囊行走";return
		body.position=ground;body.velocity=Vector3.ZERO;reset_input()
	_update_camera()

func _step_up(wish:Vector3,delta:float)->void:
	var ahead:=body.position+wish.normalized()*(RADIUS+.04+wish.length()*delta)
	var query:=PhysicsRayQueryParameters3D.create(ahead+Vector3.UP*.4,ahead-Vector3.UP*.04,WALK_MASK)
	var hit:Dictionary=editor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y<cos(deg_to_rad(45)):return
	var rise:float=hit.position.y-body.position.y+.025
	if rise<=.01 or rise>.4 or body.test_move(body.global_transform,Vector3.UP*rise):return
	var raised:=body.global_transform;raised.origin.y+=rise
	if not body.test_move(raised,wish*delta):body.global_transform=raised

func _update_camera()->void:
	var anchor:=body.position+Vector3.UP*1.35
	var basis:=Basis.from_euler(Vector3(deg_to_rad(pitch),deg_to_rad(yaw),0))
	var motion:=basis.z*distance
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=_camera_shape;query.collision_mask=WALK_MASK;query.transform=Transform3D(Basis.IDENTITY,anchor);query.motion=motion
	var cast:PackedFloat32Array=editor.get_world_3d().direct_space_state.cast_motion(query)
	var length:=maxf(.08,distance*cast[0]-.05) if cast.size()==2 else distance
	editor._camera.global_transform=Transform3D(basis,anchor+basis.z*length)
	editor._orbit_center=anchor
	editor._city.update_grid()
