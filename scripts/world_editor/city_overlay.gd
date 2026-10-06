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

func setup(value: RefCounted) -> void:
	city=value; mouse_filter=Control.MOUSE_FILTER_IGNORE; clip_contents=true
	mini=Control.new(); mini.custom_minimum_size=Vector2(200,166); mini.size=Vector2(200,166); add_child(mini)
	mini.mouse_filter=Control.MOUSE_FILTER_STOP
	mini.clip_contents=true
	mini.tooltip_text="城镇概览 · 点击定位；箭头指北（−Z），黄色框为当前正交视野"
	mini.draw.connect(draw_minimap); mini.gui_input.connect(minimap_input)
	refresh()

func refresh() -> void:
	invalidated=false; age=0
	var path: String=city.data.get("reference",{}).get("path","")
	if path!=_path:
		_path=path; texture=null; reference_error=""
		if not path.is_empty():
			if Data.Paths.allowed(path) and FileAccess.file_exists(path):
				var img:=Image.load_from_file(path)
				if img!=null and not img.is_empty(): texture=ImageTexture.create_from_image(img)
			if texture==null: reference_error="参考图文件缺失，请重新导入"
	var world: AABB=city.world_bounds("all")
	bounds=Rect2(world.position.x,world.position.z,maxf(world.size.x,1),maxf(world.size.z,1)).grow(10)
	boxes.clear()
	# The overview is schematic, capped independently of actual world records.
	var stride: int=maxi(1,ceili(city.editor._doc.records.size()/1024.0))
	for i in range(0,city.editor._doc.records.size(),stride):
		var r: Dictionary=city.editor._doc.records[i]
		if r.get("editor_hidden",false): continue
		var box: AABB=city.Geometry.bounds([r])
		boxes.append(Rect2(box.position.x,box.position.z,box.size.x,box.size.z))

func _process(_dt: float) -> void:
	if city==null: return
	age+=_dt
	if invalidated and age>=.2: refresh()
	size=city.editor._canvas.size
	mini.position=Vector2(maxf(0,size.x-mini.size.x-12),12)
	visible=not city.editor._playtest.active()
	mini.visible=city.editor._dock_tabs!=null and (city.editor._dock_tabs.current_tab==9 or not city.data.roads.nodes.is_empty() or city.data.has("reference"))
	# Saving locks the camera and authoring input. Keep the last overlay instead
	# of projecting the entire road network again for every progress-bar frame.
	if city.editor.saving(): return
	queue_redraw(); mini.queue_redraw()

func project(points: Array) -> PackedVector2Array:
	var out:=PackedVector2Array()
	for point in points:
		if city.editor._camera.is_position_behind(point): return PackedVector2Array()
		out.append(city.editor._camera.unproject_position(point))
	return out

func _draw() -> void:
	if city==null: return
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
	for edge in city.data.roads.edges:
		if edge.get("hidden",false): continue
		var color:=Color("6dc4df") if edge.kind=="bridge" else Color("efc267")
		if edge.get("locked",false): color=Color("929cb1")
		var points: Array=city.analysis.get("paths",{}).get(edge.id,[])
		var centerline:=project(points)
		if centerline.size()<2: continue
		var left: Array[Vector3]=[]; var right: Array[Vector3]=[]
		for i in points.size():
			var delta: Vector3=points[mini_i(i+1,points.size()-1)]-points[maxi(i-1,0)]
			var normal:=Vector3(-delta.z,0,delta.x).normalized()
			var width:=lerpf(edge.width_start,edge.width_end,float(i)/maxi(1,points.size()-1))
			left.append(points[i]+normal*width*.5); right.append(points[i]-normal*width*.5)
		for side in [left,right]:
			var pixels:=project(side)
			if pixels.size()>1: draw_polyline(pixels,Color(color,.38),1,true)
		draw_polyline(centerline,color,2,true)
	for node in city.data.roads.nodes:
		if node.get("hidden",false): continue
		var p:=Data.vec(node.position)
		if camera.is_position_behind(p): continue
		draw_circle(camera.unproject_position(p),4,Color("b1d7dd") if not node.get("locked",false) else Color("859099"))
	if not city.pending.is_empty():
		var pixels:=project(city.pending.map(func(p): return Data.vec(p)))
		if pixels.size()>1: draw_polyline(pixels,Color("99edb2"),3,true)
		for p in pixels: draw_circle(p,5,Color("99edb2"))
	var font:=ThemeDB.fallback_font
	var note:="正交俯视 · 上方为北（−Z）" if camera.projection==Camera3D.PROJECTION_ORTHOGONAL else "透视视图 · 右键环绕 / 中键平移"
	draw_string(font,Vector2(14,size.y-14),note,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
	if not reference_error.is_empty(): draw_string(font,Vector2(14,22),reference_error,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("ffb267"))
	if camera.projection==Camera3D.PROJECTION_ORTHOGONAL:
		var mpp: float=camera.size/maxf(size.y,1)
		var unit:=pow(10,floor(log(maxf(mpp*100,.001))/log(10)))
		var length_: float=unit/mpp
		draw_line(Vector2(14,size.y-45),Vector2(14+length_,size.y-45),Color.WHITE,2)
		draw_string(font,Vector2(14,size.y-53),str(unit)+" m",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)

func mini_i(a: int,b: int) -> int: return mini(a,b)

func mini_rect() -> Rect2:
	var scale_: float=minf((mini.size.x-20)/bounds.size.x,(mini.size.y-36)/bounds.size.y)
	var extent:=bounds.size*scale_
	return Rect2(Vector2((mini.size.x-extent.x)/2,26+(mini.size.y-36-extent.y)/2),extent)
func to_mini(point: Vector2) -> Vector2:
	var rect:=mini_rect()
	return rect.position+(point-bounds.position)/bounds.size*rect.size
func draw_minimap() -> void:
	mini.draw_style_box(preload("res://scripts/world_editor/workspace_theme.gd").panel(Color(.08,.11,.15,.94),6),Rect2(Vector2.ZERO,mini.size))
	mini.draw_string(ThemeDB.fallback_font,Vector2(10,18),"城镇概览    ↑ 北",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("b9cad5"))
	for box in boxes:
		mini.draw_rect(Rect2(to_mini(box.position),(to_mini(box.end)-to_mini(box.position)).max(Vector2.ONE)),Color(.3,.37,.42,.6))
	for edge in city.data.roads.edges:
		if edge.get("hidden",false): continue
		var pixels:=PackedVector2Array()
		for p in city.analysis.get("paths",{}).get(edge.id,[]): pixels.append(to_mini(Vector2(p.x,p.z)))
		if pixels.size()>1: mini.draw_polyline(pixels,Color("6dc4df") if edge.kind=="bridge" else Color("efc267"),1,true)
	var camera: Camera3D=city.editor._camera
	var center: Vector3=city.editor._orbit_center
	if camera.projection==Camera3D.PROJECTION_ORTHOGONAL:
		var half:=Vector2(camera.size*size.x/maxf(size.y,1),camera.size)*.5
		var from:=to_mini(Vector2(center.x,center.z)-half); var to:=to_mini(Vector2(center.x,center.z)+half)
		var clipped:=Rect2(from,to-from).intersection(Rect2(Vector2(2,25),mini.size-Vector2(4,27)))
		if clipped.has_area(): mini.draw_rect(clipped,Color("f5e8a0"),false,1.5)
	mini.draw_circle(to_mini(Vector2(center.x,center.z)),3,Color.WHITE)
func minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var rect:=mini_rect()
		if not rect.has_point(event.position): return
		var world: Vector2=bounds.position+(event.position-rect.position)/rect.size*bounds.size
		var result: Dictionary=city.set_camera({"center":[world.x,city.editor._orbit_center.y,world.y]})
		if not result.ok: city.panel.report(result)
		mini.accept_event()
