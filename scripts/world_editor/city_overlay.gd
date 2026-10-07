extends Control
const Data = preload("res://scripts/world3d/city_layout.gd")
var city: RefCounted
var texture: Texture2D
var _path := ""
var reference_error := ""
var mini: Control
var bounds := Rect2(-20,-20,40,40)
var boxes: Array[Rect2] = []
var invalidated := false
var age := 0.0
var mini_marker: Control
var _view_key: Array = []
var _marker_key: Array = []
var _had_preview := false
var _road_sides := {}
var draw_count := 0
var minimap_draw_count := 0
var _record_bounds := {}
var _changed_records := {}
var _camera_inverse := Transform3D.IDENTITY
var _projection := Projection.IDENTITY
var _projection_size := Vector2.ONE
var _near := .05
var _road_bounds := {}
var _frustum: Array[Plane] = []
var last_draw_ms := 0.0
var _roads_layer: Node2D
var _foreground: Control
var _roads_need_redraw := true
var road_draw_count := 0
var _road_projection_key: Array = []
var _road_screen_origin := Vector2.ZERO
var _road_offset := Vector2.ZERO
# Opt-in benchmark counters are monotonic: callers take differences, never
# mistake the duration of a cached draw from an earlier frame for current work.
var profile_enabled := false
var profile_cpu_us := {"process":0,"main":0,"roads":0,"foreground":0,"minimap":0,"marker":0,"projection":0}
var profile_calls := {"process":0,"main":0,"roads":0,"foreground":0,"minimap":0,"marker":0,"projection":0}

func _profile_end(stage: String, started: int) -> void:
	if not profile_enabled: return
	profile_cpu_us[stage] += Time.get_ticks_usec() - started
	profile_calls[stage] += 1

func setup(value: RefCounted) -> void:
	city=value; mouse_filter=Control.MOUSE_FILTER_IGNORE; clip_contents=true
	# A zero-size Control can be culled after negative translations even when
	# its custom drawing overlaps the viewport. Node2D uses the drawn bounds.
	_roads_layer=Node2D.new()
	add_child(_roads_layer); _roads_layer.draw.connect(draw_roads)
	_foreground=Control.new(); _foreground.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(_foreground); _foreground.draw.connect(draw_foreground)
	mini=Control.new(); mini.custom_minimum_size=Vector2(200,166); mini.size=Vector2(200,166); add_child(mini)
	mini.mouse_filter=Control.MOUSE_FILTER_STOP
	mini.clip_contents=true
	mini.tooltip_text="城镇概览 · 点击定位；箭头指北（−Z），黄色框为当前正交视野"
	mini.draw.connect(draw_minimap); mini.gui_input.connect(minimap_input)
	mini_marker=Control.new(); mini_marker.mouse_filter=Control.MOUSE_FILTER_IGNORE
	mini.add_child(mini_marker); mini_marker.draw.connect(draw_minimap_marker)
	refresh()

func refresh() -> void:
	invalidated=false; age=0
	_view_key.clear(); _marker_key.clear()
	refresh_roads()
	var path: String=city.data.get("reference",{}).get("path","")
	if path!=_path:
		_path=path; texture=null; reference_error=""
		if not path.is_empty():
			if Data.Paths.allowed(path) and FileAccess.file_exists(path):
				var img:=Image.load_from_file(path)
				if img!=null and not img.is_empty(): texture=ImageTexture.create_from_image(img)
			if texture==null: reference_error="参考图文件缺失，请重新导入"
	_record_bounds.clear(); _changed_records.clear()
	for record in city.editor._doc.records:
		_record_bounds[str(record.uuid)]=city.Geometry.bounds([record])
	_refresh_bounds()
	queue_redraw()
	if mini!=null: mini.queue_redraw()

func refresh_roads() -> void:
	_road_sides.clear()
	_road_bounds.clear()
	_roads_need_redraw=true; _road_projection_key.clear()
	for edge in city.data.roads.edges:
		var points: Array=city.analysis.get("paths",{}).get(edge.id,[])
		var left: Array[Vector3]=[]; var right: Array[Vector3]=[]
		for i in points.size():
			var delta: Vector3=points[mini_i(i+1,points.size()-1)]-points[maxi(i-1,0)]
			var normal:=Vector3(-delta.z,0,delta.x).normalized()
			var width:=lerpf(edge.width_start,edge.width_end,float(i)/maxi(1,points.size()-1))
			left.append(points[i]+normal*width*.5); right.append(points[i]-normal*width*.5)
		_road_sides[edge.id]=[left,right]
		if not points.is_empty():
			var box:=AABB(points[0],Vector3.ZERO)
			for side in [points,left,right]:
				for point: Vector3 in side: box=box.expand(point)
			_road_bounds[edge.id]=box
	queue_redraw()
	if mini!=null: mini.queue_redraw()

func invalidate_record(record: Dictionary) -> void:
	_changed_records[str(record.uuid)]=record

func _refresh_bounds() -> void:
	var world := AABB()
	var first := true
	for box: AABB in _record_bounds.values():
		world=box if first else world.merge(box); first=false
	for point in city.layout_points():
		world=AABB(point,Vector3.ZERO) if first else world.expand(point); first=false
	bounds=Rect2(world.position.x,world.position.z,maxf(world.size.x,1),maxf(world.size.z,1)).grow(10)
	boxes.clear()
	# The overview is schematic, capped independently of actual world records.
	var stride: int=maxi(1,ceili(city.editor._doc.records.size()/1024.0))
	for i in range(0,city.editor._doc.records.size(),stride):
		var r: Dictionary=city.editor._doc.records[i]
		if r.get("editor_hidden",false): continue
		var box: AABB=_record_bounds[str(r.uuid)]
		boxes.append(Rect2(box.position.x,box.position.z,box.size.x,box.size.z))

func _process(_dt: float) -> void:
	if city==null: return
	var measured := Time.get_ticks_usec() if profile_enabled else 0
	age+=_dt
	if invalidated and age>=.2: refresh()
	elif not _changed_records.is_empty() and age>=.2:
		for id: String in _changed_records: _record_bounds[id]=city.Geometry.bounds([_changed_records[id]])
		_changed_records.clear(); age=0; _refresh_bounds(); mini.queue_redraw()
	size=city.editor._canvas.size
	mini.position=Vector2(maxf(0,size.x-mini.size.x-12),12)
	visible=not city.editor._playtest.active()
	mini.visible=city.editor._dock_tabs!=null and (city.editor._dock_tabs.current_tab==9 or not city.data.roads.nodes.is_empty() or city.data.has("reference"))
	# Saving locks the camera and authoring input. Keep the last overlay instead
	# of projecting the entire road network again for every progress-bar frame.
	if city.editor.saving():
		_profile_end("process", measured)
		return
	var camera: Camera3D=city.editor._camera
	prepare_projection()
	var view_key: Array=[camera.get_camera_transform(),camera.projection,camera.size,camera.fov,camera.keep_aspect,camera.frustum_offset,camera.near,camera.far,size]
	var preview: bool=city.busy() or not city.pending.is_empty() or not city.editor._blocks.overlay_plan.is_empty() or not city.editor._scatter.overlay_plan.is_empty() or not city.editor._waterways.overlay_plan.is_empty() or not city.editor._fortifications.overlay_plan.is_empty()
	var view_changed:bool=view_key!=_view_key
	if view_changed or preview or _had_preview:
		_view_key=view_key; queue_redraw(); _foreground.queue_redraw()
		# Preview geometry belongs to the main/foreground layers. Existing roads
		# only change with their own cache invalidation or a changed projection.
		if view_changed and camera.projection!=Camera3D.PROJECTION_ORTHOGONAL: _roads_need_redraw=true
	_roads_layer.position=_road_offset
	if _roads_need_redraw:
		_roads_need_redraw=false; _roads_layer.queue_redraw()
	_had_preview=preview
	var marker_key: Array=[city.editor._orbit_center,camera.projection,camera.size,size,mini.size,bounds]
	if marker_key!=_marker_key:
		_marker_key=marker_key; mini_marker.queue_redraw()
	_profile_end("process", measured)

func project(points: Array) -> PackedVector2Array:
	# The engine transforms the packed vertices in one call. Preserve every
	# sample and the same homogeneous projection/near-plane rejection.
	var local_points: PackedVector3Array=_camera_inverse*PackedVector3Array(points)
	var out:=PackedVector2Array()
	out.resize(local_points.size())
	for index in local_points.size():
		var local:=local_points[index]
		if local.z > -_near: return PackedVector2Array()
		var clip: Vector4=_projection*Vector4(local.x,local.y,local.z,1.)
		out[index]=Vector2(clip.x/clip.w*.5+.5,-clip.y/clip.w*.5+.5)*_projection_size
	return out

func project_local(point: Vector3) -> Vector2:
	var clip: Vector4=_projection*Vector4(point.x,point.y,point.z,1.)
	return Vector2(clip.x/clip.w*.5+.5,-clip.y/clip.w*.5+.5)*_projection_size

func prepare_projection() -> void:
	var measured := Time.get_ticks_usec() if profile_enabled else 0
	var camera: Camera3D=city.editor._camera
	_camera_inverse=camera.get_camera_transform().affine_inverse()
	_projection=camera.get_camera_projection()
	_projection_size=camera.get_viewport().get_visible_rect().size
	_near=camera.near
	_frustum=camera.get_frustum()
	var key: Array=[camera.global_basis,_projection,_projection_size,_camera_inverse.origin.z]
	if camera.projection==Camera3D.PROJECTION_ORTHOGONAL:
		# Orthographic pan is an exact 2D translation at every world height.
		# Keep projected curve samples until zoom/orientation/depth/data changes.
		if key!=_road_projection_key:
			_roads_need_redraw=true; _road_projection_key=key
			_road_screen_origin=project_local(_camera_inverse*Vector3.ZERO)
		_road_offset=project_local(_camera_inverse*Vector3.ZERO)-_road_screen_origin
	else:
		_road_projection_key.clear(); _road_offset=Vector2.ZERO
	_profile_end("projection", measured)

func road_in_view(id: String) -> bool:
	if not _road_bounds.has(id): return false
	var box: AABB=_road_bounds[id]
	var center:=box.get_center(); var extent:=box.size*.5
	for plane: Plane in _frustum:
		# Include the screen-space stroke fringe even for a far-away camera.
		var fringe: float=maxf(.01,center.distance_to(city.editor._camera.global_position)*.02)
		if plane.distance_to(center)>plane.normal.abs().dot(extent)+fringe: return false
	return true

func _draw() -> void:
	if city==null: return
	var started:=Time.get_ticks_usec()
	draw_count+=1
	prepare_projection()
	var camera: Camera3D=city.editor._camera
	var wall: Dictionary=city.editor._fortifications.overlay_plan
	if wall.has("settings"):
		var points: Array=wall.get("outline",wall.settings.points).map(func(p):return Vector3(p[0],wall.settings.base_height+.2,p[1]))
		if wall.settings.closed and not points.is_empty(): points.append(points[0])
		var pixels:=project(points)
		if pixels.size()>1: draw_polyline(pixels,Color("dcc49a"),4,true)
		for zone in wall.get("layout_zones",[]):
			var ring: Array=[]
			for i in 65:
				var angle: float=TAU*i/64
				ring.append(Vector3(zone.center[0]+cos(angle)*zone.radius,wall.settings.base_height+.3,zone.center[1]+sin(angle)*zone.radius))
			var projected:=project(ring)
			if projected.size()>1: draw_polyline(projected,Color(.95,.45,.25,.55),1.5,true)
		for gate in wall.get("gates",[]):
			var at:=Data.vec(gate.center)
			if not camera.is_position_behind(at): draw_circle(camera.unproject_position(at),7,Color("91dbb6"))
	var river: Dictionary=city.editor._waterways.overlay_plan
	if river.has("outline"):
		var y: float=river.settings.bank_height+.2
		var outline:=project(river.outline.map(func(p):return Vector3(p[0],y,p[1])))
		if outline.size()>2: draw_colored_polygon(outline,Color(.2,.65,.85,.2)); outline.append(outline[0]); draw_polyline(outline,Color("71cadf"),3,true)
		for bridge in river.bridges:
			var border:=project(bridge.polygon.map(func(p):return Vector3(p[0],y,p[1])))
			if border.size()>2: border.append(border[0]); draw_polyline(border,Color("eadba7"),3,true)
	var scatter: Dictionary=city.editor._scatter.overlay_plan
	if scatter.has("settings"):
		var y: float=scatter.settings.height+.15
		var border:=project(scatter.settings.polygon.map(func(p):return Vector3(p[0],y,p[1])))
		if border.size()>2: border.append(border[0]); draw_polyline(border,Color("b3e784"),3,true)
		for item in scatter.placements:
			var outline:=project(item.polygon.map(func(p):return Vector3(p[0],y,p[1])))
			if outline.size()>2:
				draw_colored_polygon(outline,Color(.35,.85,.4,.24)); outline.append(outline[0]); draw_polyline(outline,Color("7fc686"),1.5,true)
	var preview: Dictionary=city.editor._blocks.overlay_plan
	for block in preview.get("blocks",[]):
		var points: Array=[]
		for p in block.polygon: points.append(Vector3(p[0],block.height+.1,p[1]))
		var pixels:=project(points)
		if pixels.size()>2: pixels.append(pixels[0]); draw_polyline(pixels,Color("c5d6a6"),2,true)
	for lot in preview.get("lots",[]):
		var points: Array=[]
		for p in lot.polygon: points.append(Vector3(p[0],lot.position[1]+.12,p[1]))
		var pixels:=project(points)
		var color:=Color("82d9a4") if lot.status=="ready" else (Color("85b4ec") if lot.status in ["retained","missing"] else (Color("9399a4") if lot.status=="pending" else Color("e79a8a")))
		if pixels.size()>2:
			draw_colored_polygon(pixels,Color(color,.19)); pixels.append(pixels[0]); draw_polyline(pixels,Color(color,.85),1.5,true)
		if lot.has("building_polygon"):
			var footprint: Array=[]
			for p in lot.building_polygon: footprint.append(Vector3(p[0],lot.position[1]+.15,p[1]))
			var outline:=project(footprint)
			if outline.size()>2:
				draw_colored_polygon(outline,Color(color,.3)); outline.append(outline[0]); draw_polyline(outline,color,2,true)
				var center: Vector2=(outline[0]+outline[2])*.5
				draw_string(ThemeDB.fallback_font,center,str(int(lot.parameters.floors))+" 层",HORIZONTAL_ALIGNMENT_CENTER,-1,12,Color.WHITE)
		if lot.has("access"):
			var access:=project(lot.access.map(func(p):return Data.vec(p)+Vector3.UP*.15))
			if access.size()==2: draw_line(access[0],access[1],Color("f7eab3"),3,true); draw_circle(access[1],3,Color("f7eab3"))
	var ref: Dictionary=city.data.get("reference",{})
	if not ref.is_empty() and ref.visible and texture!=null and camera.projection==Camera3D.PROJECTION_ORTHOGONAL:
		var corners:=project(city.reference_corners(ref))
		if corners.size()==4: draw_polygon(corners,PackedColorArray([Color(1,1,1,ref.opacity)]),PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]),texture)
	for zone in city.data.get("zones",[]):
		if zone.get("hidden",false): continue
		var points: Array=[]
		for p in zone.polygon: points.append(Vector3(p[0],zone.min_y,p[1]))
		var polygon:=project(points)
		if polygon.size()<3: continue
		var color:=Color("e58c8c") if zone.purpose=="no_build" else (Color("91c396") if zone.purpose=="no_vegetation" else Color("a29fdc"))
		draw_colored_polygon(polygon,Color(color,.16)); polygon.append(polygon[0]); draw_polyline(polygon,Color(color,.8),2,true)
	last_draw_ms=(Time.get_ticks_usec()-started)/1000.0
	_profile_end("main", started)

func draw_roads() -> void:
	var measured := Time.get_ticks_usec() if profile_enabled else 0
	road_draw_count+=1
	var camera: Camera3D=city.editor._camera
	_roads_layer.draw_set_transform(-_road_offset)
	for edge in city.data.roads.edges:
		if edge.get("hidden",false): continue
		if camera.projection!=Camera3D.PROJECTION_ORTHOGONAL and not road_in_view(str(edge.id)): continue
		var color:=Color("6dc4df") if edge.kind=="bridge" else Color("efc267")
		if edge.get("locked",false): color=Color("929cb1")
		var points: Array=city.analysis.get("paths",{}).get(edge.id,[])
		var centerline:=project(points)
		if centerline.size()<2: continue
		var sides: Array=_road_sides.get(edge.id,[])
		for index in sides.size():
			var pixels:=project(sides[index])
			if pixels.size()>1: _roads_layer.draw_polyline(pixels,Color(color,.38),1,true)
		_roads_layer.draw_polyline(centerline,color,2,true)
	for node in city.data.roads.nodes:
		if node.get("hidden",false): continue
		var p: Vector3=_camera_inverse*Data.vec(node.position)
		if p.z > -_near: continue
		_roads_layer.draw_circle(project_local(p),4,Color("b1d7dd") if not node.get("locked",false) else Color("859099"))
	_profile_end("roads", measured)

func draw_foreground() -> void:
	var measured := Time.get_ticks_usec() if profile_enabled else 0
	var camera: Camera3D=city.editor._camera
	if not city.pending.is_empty():
		var pixels:=project(city.pending.map(func(p): return Data.vec(p)))
		if pixels.size()>1: _foreground.draw_polyline(pixels,Color("99edb2"),3,true)
		for p in pixels: _foreground.draw_circle(p,5,Color("99edb2"))
	var font:=ThemeDB.fallback_font
	var note:="正交俯视 · 上方为北（−Z）" if camera.projection==Camera3D.PROJECTION_ORTHOGONAL else "透视视图 · 右键环绕 / 中键平移"
	if city.editor._walk_mode!=null and city.editor._walk_mode.active:note="胶囊行走 · WASD / Shift / 空格 · 右键转向 · 左键编辑 · F6 退出"
	_foreground.draw_string(font,Vector2(14,size.y-14),note,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
	if not reference_error.is_empty(): _foreground.draw_string(font,Vector2(14,22),reference_error,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("ffb267"))
	if camera.projection==Camera3D.PROJECTION_ORTHOGONAL:
		var mpp: float=camera.size/maxf(size.y,1)
		var unit:=pow(10,floor(log(maxf(mpp*100,.001))/log(10)))
		var length_: float=unit/mpp
		_foreground.draw_line(Vector2(14,size.y-45),Vector2(14+length_,size.y-45),Color.WHITE,2)
		_foreground.draw_string(font,Vector2(14,size.y-53),str(unit)+" m",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)
	_profile_end("foreground", measured)

func mini_i(a: int,b: int) -> int: return mini(a,b)

func mini_rect() -> Rect2:
	var scale_: float=minf((mini.size.x-20)/bounds.size.x,(mini.size.y-36)/bounds.size.y)
	var extent:=bounds.size*scale_
	return Rect2(Vector2((mini.size.x-extent.x)/2,26+(mini.size.y-36-extent.y)/2),extent)
func to_mini(point: Vector2) -> Vector2:
	var rect:=mini_rect()
	return rect.position+(point-bounds.position)/bounds.size*rect.size
func draw_minimap() -> void:
	var measured := Time.get_ticks_usec() if profile_enabled else 0
	minimap_draw_count+=1
	mini.draw_style_box(preload("res://scripts/world_editor/workspace_theme.gd").panel(Color(.08,.11,.15,.94),6),Rect2(Vector2.ZERO,mini.size))
	mini.draw_string(ThemeDB.fallback_font,Vector2(10,18),"城镇概览    ↑ 北",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("b9cad5"))
	for box in boxes:
		mini.draw_rect(Rect2(to_mini(box.position),(to_mini(box.end)-to_mini(box.position)).max(Vector2.ONE)),Color(.3,.37,.42,.6))
	for edge in city.data.roads.edges:
		if edge.get("hidden",false): continue
		var pixels:=PackedVector2Array()
		for p in city.analysis.get("paths",{}).get(edge.id,[]): pixels.append(to_mini(Vector2(p.x,p.z)))
		if pixels.size()>1: mini.draw_polyline(pixels,Color("6dc4df") if edge.kind=="bridge" else Color("efc267"),1,true)
	_profile_end("minimap", measured)

func draw_minimap_marker() -> void:
	var measured := Time.get_ticks_usec() if profile_enabled else 0
	var camera: Camera3D=city.editor._camera
	var center: Vector3=city.editor._orbit_center
	if camera.projection==Camera3D.PROJECTION_ORTHOGONAL:
		var half:=Vector2(camera.size*size.x/maxf(size.y,1),camera.size)*.5
		var from:=to_mini(Vector2(center.x,center.z)-half); var to:=to_mini(Vector2(center.x,center.z)+half)
		var clipped:=Rect2(from,to-from).intersection(Rect2(Vector2(2,25),mini.size-Vector2(4,27)))
		if clipped.has_area(): mini_marker.draw_rect(clipped,Color("f5e8a0"),false,1.5)
	mini_marker.draw_circle(to_mini(Vector2(center.x,center.z)),3,Color.WHITE)
	_profile_end("marker", measured)
func minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var rect:=mini_rect()
		if not rect.has_point(event.position): return
		var world: Vector2=bounds.position+(event.position-rect.position)/rect.size*bounds.size
		var result: Dictionary=city.set_camera({"center":[world.x,city.editor._orbit_center.y,world.y]})
		if not result.ok: city.panel.report(result)
		mini.accept_event()
