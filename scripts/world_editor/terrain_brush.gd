extends Control
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
var editor: Node3D
var active:=false
var pointer_down:=false
var target_id:=""
var options: Dictionary={}
var before: Array=[]
var before_state:Dictionary={}
var was_dirty:=false
var changed_ids:Array[String]=[]
var last:=Vector2(INF,INF)
var hover:=Vector3(INF,INF,INF)

func setup(value: Node3D) -> void:
	editor=value; mouse_filter=MOUSE_FILTER_IGNORE; set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func begin(id: String, settings: Dictionary) -> Dictionary:
	editor._finish_edits()
	var ready: Dictionary=editor._gameplay.guard()
	if not ready.ok: return ready
	var record: Dictionary=editor._doc._find(id)
	if not record.has("terrain_mesh") or not editor._record_editable(record): return Terrain.fail("请在地形列表中选择可编辑地形")
	var validation:=Terrain.S.validate(settings.merged({"id":id,"points":[[record.position[0],record.position[2]]]}),Terrain.stroke_schema())
	if not validation.is_empty(): return Terrain.fail(validation)
	editor._set_mode(1); editor._dock_tabs.current_tab=10; editor._gizmo.visible=false
	target_id=id; options=settings.duplicate(true); active=true
	return {"ok":true}
func cancel() -> void:
	finish(); active=false; hover=Vector3(INF,INF,INF); queue_redraw()
func finish(rollback: bool=false) -> void:
	if not pointer_down: return
	pointer_down=false
	if not rollback and before!=editor._doc.records:
		# Terrain previews every dab; refreeze the dependent structure only once
		# on mouse release. Failure rolls the entire gesture back atomically.
		var followed:Dictionary=editor._terrain.finish_followers(changed_ids)
		if not followed.ok:rollback=true;editor._status.text=str(followed.error)
		else:
			for id:String in followed.ids:
				if not changed_ids.has(id):changed_ids.append(id)
	if rollback:
		var refresh_ids: Array[String]=changed_ids.duplicate()
		editor._doc.apply_recovery(before_state); editor._dirty=was_dirty; editor._refresh_records(refresh_ids)
	elif before!=editor._doc.records: editor._doc.commit_recovery_change(before_state)
	before=[]; before_state={}; changed_ids.clear(); last=Vector2(INF,INF); editor._refresh_selection()
	if editor._terrain_panel!=null: editor._terrain_panel.refresh(target_id)
func pick(screen: Vector2) -> Vector3:
	if not Rect2(Vector2.ZERO,editor._canvas.size).has_point(screen): return Vector3(INF,INF,INF)
	var record: Dictionary=editor._doc._find(target_id)
	if record.is_empty(): return Vector3(INF,INF,INF)
	var origin: Vector3=editor._camera.project_ray_origin(screen); var direction: Vector3=editor._camera.project_ray_normal(screen)
	var query:=PhysicsRayQueryParameters3D.create(origin,origin+direction*editor._camera.far)
	query.hit_back_faces=false
	var hit: Dictionary=editor.get_world_3d().direct_space_state.intersect_ray(query)
	var targets:Array=preload("res://scripts/world3d/terrain_stroke_batch.gd").connected(editor._doc.records,record) if options.get("cross_tiles",true) else [record]
	if not hit.is_empty() and hit.normal.y>.01:
		var hit_id:=preload("res://scripts/world3d/fortification_collision_batcher.gd").hit_uuid(hit)
		for tile:Dictionary in targets:
			if tile.uuid==hit_id:return hit.position
	# A hole has no top-face hit. Keep all connected tiles pickable, otherwise a
	# cross-tile hole could only be filled after changing the selected seed tile.
	var limit:float=editor._camera.far if hit.is_empty() else origin.distance_to(hit.position)+.01
	return plane_pick(targets,origin,direction,limit)

static func plane_pick(targets:Array,origin:Vector3,direction:Vector3,limit:float)->Vector3:
	var nearest:=Vector3(INF,INF,INF);var distance:=limit
	for tile:Dictionary in targets:
		var at:Variant=Plane(Vector3.UP,float(tile.position[1])).intersects_ray(origin,direction)
		if at==null:continue
		var local:Vector3=Terrain.transform(tile).affine_inverse()*at
		if not is_finite(Terrain.sample(tile,local,true)):continue
		var measured:float=origin.distance_to(at)
		if measured<=distance:nearest=at;distance=measured
	return nearest
func dab(screen: Vector2) -> void:
	var at:=pick(screen)
	if not at.is_finite(): return
	var p:=Vector2(at.x,at.z)
	if last.is_finite() and last.distance_to(p)<maxf(float(options.radius)*.25,.125): return
	var points: Array=[[p.x,p.y]] if not last.is_finite() else [[last.x,last.y],[p.x,p.y]]
	# Exclude the already applied first stamp of a segment by using its first interval.
	if last.is_finite():
		var count:=maxi(1,ceili(last.distance_to(p)/maxf(float(options.radius)*.25,.125)))
		var first:=last.lerp(p,1.0/count); points=[[first.x,first.y],[p.x,p.y]]
	if options.get("shape","circle")=="rectangle":points=[[p.x,p.y]]
	var result: Dictionary=editor._terrain.sculpt(options.merged({"id":target_id,"points":points}),true)
	if not result.ok:
		finish(true); editor._status.text=str(result.error); return
	for id:String in result.get("changed_ids",[]):
		if not changed_ids.has(id):changed_ids.append(id)
	last=p; editor._status.text="地形笔刷 · 松开提交这一笔 · Esc 撤销当前笔画并退出"
func input(event: InputEvent) -> bool:
	if not active: return false
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		finish(true); cancel(); editor._status.text="已退出地形笔刷"; return true
	if pointer_down and event is InputEventKey: return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed and editor._canvas.get_global_rect().has_point(event.position):
			before_state=editor._doc.recovery_snapshot(); before=before_state.records; was_dirty=editor._dirty; pointer_down=true; last=Vector2(INF,INF); dab(event.position-editor._canvas.global_position); return true
		if not event.pressed and pointer_down:
			dab(event.position-editor._canvas.global_position); finish(); return true
	if event is InputEventMouseMotion and pointer_down:
		if editor._canvas.get_global_rect().has_point(event.position): dab(event.position-editor._canvas.global_position)
		return true
	# Failed strokes remain in brush mode until release; never fall through to object dragging.
	if event is InputEventMouseMotion and (event.button_mask&MOUSE_BUTTON_MASK_LEFT)!=0: return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and editor._canvas.get_global_rect().has_point(event.position): return true
	return false
func _process(_dt: float) -> void:
	if not active: return
	hover=pick(get_global_mouse_position()-editor._canvas.global_position); queue_redraw()
func _draw() -> void:
	if not active or not hover.is_finite(): return
	var record: Dictionary=editor._doc._find(target_id)
	if record.is_empty(): return
	var world:=Terrain.transform(record); var inverse:=world.affine_inverse(); var ring:=PackedVector2Array()
	for i in 65:
		var angle:=TAU*i/64; var p:=hover+Vector3(cos(angle),0,sin(angle))*float(options.radius)
		if options.get("shape","circle")=="rectangle":
			var quarter:=i/16
			var t:=float(i%16)/16.
			var half:=Vector2(float(options.plot_width),float(options.plot_depth))*.5
			var corners:Array[Vector2]=[Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]
			var point:Vector2=corners[quarter%4].lerp(corners[(quarter+1)%4],t).rotated(-deg_to_rad(float(options.get("plot_yaw",0))))
			p=hover+Vector3(point.x,0,point.y)
		var local:=inverse*p; var h:=Terrain.sample(record,local,true)
		if is_finite(h): local.y=h+.04; p=world*local
		if editor._camera.is_position_behind(p): return
		ring.append(editor._camera.unproject_position(p))
	draw_polyline(ring,Color(1,.73,.15,.95),2.0,true)
