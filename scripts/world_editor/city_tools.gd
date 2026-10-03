extends RefCounted
const Data = preload("res://scripts/world3d/city_layout.gd")
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
var editor: Node3D
var panel: VBoxContainer
var overlay: Control
var analysis := {"ok":true,"nodes":{},"paths":{},"diagnostics":[]}
var data := Data.defaults()
var drawing := false
var zone_draft: Dictionary = {}
var scatter_draft := false
var waterway_draft := false
var bridge_draft := false
var fortification_draft := false
var pending: Array = []
var draw_width := 8.0
var draw_height := 0.0
var draw_kind := "ground"
var _angles := Vector2(-35,0)
var _distance := 15.0
var drag_node := {}
var drag_screen := Vector2.ZERO
var drag_anchor := Vector3.ZERO
var drag_token := ""
var drag_moved := false

func busy() -> bool:
	return drawing or not drag_node.is_empty()

func refresh() -> void:
	data = Data.resolve(editor._doc.map_meta)
	analysis = Data.analyze(data.roads)
	if panel != null: panel.refresh()
	if overlay != null: overlay.refresh()

func guard() -> Dictionary:
	if busy(): return Data.fail("请先提交或取消道路草案 / 节点拖动")
	return editor._gameplay.guard()

func commit(value: Dictionary) -> Dictionary:
	if not Data.valid({"editor_layout":value}): return Data.fail("城市布局数据无效")
	if value == Data.resolve(editor._doc.map_meta): return {"ok":true,"changed":false}
	editor._doc.checkpoint_recovery()
	editor._doc.map_meta.editor_layout = value
	editor._dirty = true
	refresh()
	return {"ok":true,"changed":true}

func state() -> Dictionary:
	var value := Data.resolve(editor._doc.map_meta)
	var manifest: Dictionary=value.get("road_surface",{})
	return {"ok":true,"layout":value,"road_token":Data.token(value.roads),"zone_token":JSON.stringify(value.get("zones",[])).sha256_text(),"camera":camera_state(),"bounds":bounds_data("all"),"diagnostics":analysis.get("diagnostics",[]),"road_drawing":drawing,"road_node_drag":not drag_node.is_empty(),"runtime_geometry":not manifest.get("parts",[]).is_empty(),"surface_stale":not manifest.is_empty() and manifest.graph_token!=Data.token(value.roads)}

func camera_state() -> Dictionary:
	var top: bool = editor._camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	if not top: _angles = Vector2(editor._camera.rotation_degrees.x,wrapf(editor._camera.rotation_degrees.y,-180,180))
	return {"projection":"top" if top else "perspective", "center":Data.xyz(editor._orbit_center), "distance":_distance if top else editor._camera.position.distance_to(editor._orbit_center), "span":maxf(2,editor._camera.size), "yaw":_angles.y, "pitch":clampf(_angles.x,-89,-5)}

func set_camera(changes: Dictionary) -> Dictionary:
	var ready := guard()
	if not ready.ok: return ready
	var error := Data.S.validate(changes,Data.camera_schema())
	if not error.is_empty(): return Data.fail(error)
	var value := camera_state(); value.merge(changes,true)
	apply_camera(value)
	return {"ok":true,"camera":camera_state()}

func apply_camera(value: Dictionary) -> void:
	_distance=value.distance
	editor._orbit_center = Data.vec(value.center)
	_angles = Vector2(value.pitch,value.yaw)
	editor._camera.keep_aspect = Camera3D.KEEP_HEIGHT
	editor._camera.near = .05; editor._camera.far = 40000
	editor._camera.size = value.span
	if value.projection == "top":
		editor._camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		editor._camera.rotation_degrees = Vector3(-90,0,0)
		# Keep tall existing buildings between the near/far planes when zoomed closely overhead.
		editor._camera.position = editor._orbit_center+Vector3.UP*maxf(value.distance,10000)
	else:
		editor._camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		editor._camera.rotation_degrees = Vector3(value.pitch,value.yaw,0)
		editor._camera.position = editor._orbit_center+editor._camera.basis.z*value.distance
	update_grid()

func zoom(factor: float) -> void:
	if editor._camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		editor._camera.size = clampf(editor._camera.size*factor,2,10000)
	else:
		editor._camera.position = editor._orbit_center+editor._camera.basis.z*clampf(editor._camera.position.distance_to(editor._orbit_center)*factor,2,10000)
	update_grid()

func pan(relative: Vector2) -> void:
	var height: float = maxf(editor._canvas.size.y,1)
	var span: float = editor._camera.size if editor._camera.projection == Camera3D.PROJECTION_ORTHOGONAL else 2*editor._camera.position.distance_to(editor._orbit_center)*tan(deg_to_rad(editor._camera.fov*.5))
	var offset: Vector3 = (-editor._camera.global_basis.x*relative.x+editor._camera.global_basis.y*relative.y)*span/height
	editor._camera.position += offset; editor._orbit_center += offset
	update_grid()

func orbit(relative: Vector2) -> void:
	if editor._camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		var value := camera_state(); value.projection="perspective"; value.distance=clampf(value.span,2,10000); apply_camera(value)
	var distance: float = editor._camera.position.distance_to(editor._orbit_center)
	editor._camera.rotation.x = clampf(editor._camera.rotation.x-relative.y*.005,deg_to_rad(-89),deg_to_rad(-5))
	editor._camera.rotation.y -= relative.x*.005
	editor._camera.position = editor._orbit_center+editor._camera.basis.z*distance
	update_grid()

func update_grid() -> void:
	if editor._grid == null: return
	var span: float = editor._camera.size if editor._camera.projection == Camera3D.PROJECTION_ORTHOGONAL else editor._camera.position.distance_to(editor._orbit_center)
	var step := pow(10.0,floor(log(maxf(span/20,1))/log(10.0)))
	editor._grid.scale = Vector3(step,1,step)
	editor._grid.position = Vector3(snappedf(editor._orbit_center.x,step),0,snappedf(editor._orbit_center.z,step))

func layout_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for path in analysis.get("paths",{}).values(): points.append_array(path)
	for node in data.roads.nodes: points.append(Data.vec(node.position))
	for zone in data.get("zones",[]):
		for p in zone.polygon: points.append(Vector3(p[0],zone.min_y,p[1]))
	if data.has("reference"): points.append_array(reference_corners(data.reference))
	return points

func world_bounds(target: String) -> AABB:
	var points: Array[Vector3] = []
	if target in ["all","selection"]:
		var records: Array = editor._selection_tools.records() if target=="selection" else editor._doc.records
		for record in records: points.append_array(Geometry.corners(record))
	if target in ["all","layout"]: points.append_array(layout_points())
	if points.is_empty(): return AABB(Vector3(-20,0,-20),Vector3(40,0,40))
	var result := AABB(points[0],Vector3.ZERO)
	for point in points: result=result.expand(point)
	return result

func bounds_data(target: String) -> Dictionary:
	var bounds := world_bounds(target)
	return {"from":Data.xyz(bounds.position),"to":Data.xyz(bounds.end)}

func focus(args: Dictionary) -> Dictionary:
	var ready := guard()
	if not ready.ok: return ready
	var target := str(args.get("target","all"))
	if target == "selection" and editor._selection_tools.ids.is_empty(): return Data.fail("当前没有选择物件")
	var bounds: AABB
	if target == "region":
		if not args.has("from") or not args.has("to"): return Data.fail("区域定位需要 from 和 to")
		var a := Data.vec(args.from); var b := Data.vec(args.to)
		bounds = AABB(a.min(b),a.max(b)-a.min(b))
		if bounds.size.length() < .01: return Data.fail("定位区域不能为空")
	else:
		if args.has("from") or args.has("to"): return Data.fail("只有 region 定位使用 from/to")
		bounds = world_bounds(target)
	var value := camera_state(); value.center=Data.xyz(bounds.get_center()); value.projection=args.get("projection",value.projection)
	var aspect: float = maxf(editor._canvas.size.x,1)/maxf(editor._canvas.size.y,1)
	if value.projection == "top":
		var span := maxf(bounds.size.z,bounds.size.x/aspect)*1.1
		if span > 10000: return Data.fail("定位范围超过当前 10 公里视野上限")
		value.span=maxf(span,4)
	else:
		var basis := Basis.from_euler(Vector3(deg_to_rad(value.pitch),deg_to_rad(value.yaw),0))
		var tangent := tan(deg_to_rad(editor._camera.fov*.5)); var distance := 3.0
		for i in 8:
			var p := Vector3(bounds.end.x if i&1 else bounds.position.x,bounds.end.y if i&2 else bounds.position.y,bounds.end.z if i&4 else bounds.position.z)-bounds.get_center()
			p = basis.inverse()*p
			distance=maxf(distance,p.z+maxf(absf(p.y)/tangent,absf(p.x)/(tangent*aspect))*1.1)
		if distance > 10000: return Data.fail("定位范围超过当前 10 公里视距上限")
		value.distance=distance
	var validation:=Data.S.validate(value,Data.camera_schema())
	if not validation.is_empty(): return Data.fail(validation)
	apply_camera(value)
	return {"ok":true,"camera":camera_state(),"bounds":{"from":Data.xyz(bounds.position),"to":Data.xyz(bounds.end)}}

static func reference_corners(ref: Dictionary) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var half := Vector2(ref.pixel_size[0],ref.pixel_size[1])*float(ref.meters_per_pixel)*.5
	var basis := Basis(Vector3.UP,deg_to_rad(ref.yaw))
	for p in [Vector3(-half.x,0,-half.y),Vector3(half.x,0,-half.y),Vector3(half.x,0,half.y),Vector3(-half.x,0,half.y)]: result.append(Data.vec(ref.center)+basis*p)
	return result

func set_reference(args: Dictionary) -> Dictionary:
	var ready := guard()
	if not ready.ok: return ready
	var value := Data.resolve(editor._doc.map_meta); var ref: Dictionary = value.get("reference",{})
	if ref.get("locked",false):
		for key in args:
			if key not in ["locked","visible","opacity"]: return Data.fail("底图已锁定，请先单独解锁再修改标定或移除")
	if args.get("remove",false):
		if args.size()!=1: return Data.fail("移除底图不能同时修改参数")
		value.erase("reference"); return commit(value)
	var png := PackedByteArray(); var target := ""
	if args.has("path"):
		var path := str(args.path)
		if not Data.Paths.allowed(path) or path.get_extension().to_lower() not in ["png","jpg","jpeg","webp"]: return Data.fail("请选择外部内容目录内的 PNG / JPEG / WebP 底图")
		var file := FileAccess.open(path,FileAccess.READ)
		if file==null or file.get_length()>16777216: return Data.fail("底图不可读或超过 16 MiB")
		file.close()
		var img := Image.load_from_file(path)
		if img==null or img.is_empty() or maxi(img.get_width(),img.get_height())>4096: return Data.fail("底图最大支持 4096×4096")
		png=img.save_png_to_buffer()
		var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(png)
		target=Data.Paths.cache_directory("layout_references").path_join(hash.finish().hex_encode()+".png")
		ref={"path":target,"pixel_size":[img.get_width(),img.get_height()],"center":[0,0,0],"meters_per_pixel":1.0,"yaw":0.0,"opacity":.55,"visible":true,"locked":false}
	if ref.is_empty(): return Data.fail("请先导入参考底图")
	for key in args:
		if key not in ["path","remove"]: ref[key]=args[key]
	value.reference=ref
	if not Data.valid({"editor_layout":value}): return Data.fail("底图参数无效或覆盖范围超过 10 公里")
	# Validate the complete transaction before writing an immutable, content-addressed image.
	if not target.is_empty() and not FileAccess.file_exists(target):
		if not Data.Paths.allowed(target) or DirAccess.make_dir_recursive_absolute(target.get_base_dir())!=OK: return Data.fail("无法创建底图库")
		var err := preload("res://scripts/world_editor/surface_material_library.gd")._write(target,png)
		if err!=OK: return Data.fail("无法保存底图："+error_string(err))
	return commit(value)

func calibrate(args: Dictionary) -> Dictionary:
	var ready := guard()
	if not ready.ok: return ready
	var value := Data.resolve(editor._doc.map_meta)
	if not value.has("reference"): return Data.fail("请先导入参考底图")
	var ref: Dictionary=value.reference
	if ref.locked: return Data.fail("底图已锁定，请先解锁")
	var a:=Vector2(args.pixels[0][0],args.pixels[0][1]); var b:=Vector2(args.pixels[1][0],args.pixels[1][1])
	var pixel_bounds:=Rect2(Vector2.ZERO,Vector2(ref.pixel_size[0],ref.pixel_size[1]))
	if not pixel_bounds.has_point(a) or not pixel_bounds.has_point(b) or a.distance_to(b)<4: return Data.fail("标定像素点需在图片内且相距至少 4 像素")
	var p:=Data.vec(args.world[0]); var q:=Data.vec(args.world[1])
	if absf(p.y-q.y)>.001 or p.distance_to(q)<.1: return Data.fail("标定世界点需同高且相距至少 0.1 米")
	ref.meters_per_pixel=p.distance_to(q)/a.distance_to(b)
	ref.yaw=wrapf(rad_to_deg((b-a).angle()-Vector2(q.x-p.x,q.z-p.z).angle()),-180,180)
	var offset: Vector2=(a-pixel_bounds.size*.5)*float(ref.meters_per_pixel)
	ref.center=Data.xyz(p-Basis(Vector3.UP,deg_to_rad(ref.yaw))*Vector3(offset.x,0,offset.y))
	return commit(value)

func bookmark(args: Dictionary, remove: bool = false) -> Dictionary:
	var ready:=guard()
	if not ready.ok: return ready
	var value:=Data.resolve(editor._doc.map_meta)
	var id:=str(args.get("id","view_"+Crypto.new().generate_random_bytes(6).hex_encode()))
	if not Data.valid_id(id): return Data.fail("书签 ID 无效")
	var index:=-1
	for i in value.bookmarks.size():
		if value.bookmarks[i].id==id: index=i; break
	if remove:
		if index<0: return Data.fail("书签不存在")
		value.bookmarks.remove_at(index)
	else:
		var entry:={"id":id,"name":str(args.name).strip_edges(),"camera":camera_state()}
		if index<0: value.bookmarks.append(entry)
		else: value.bookmarks[index]=entry
	var result:=commit(value); result.id=id; return result

func recall(id: String) -> Dictionary:
	for entry in Data.resolve(editor._doc.map_meta).bookmarks:
		if entry.id==id: return set_camera(entry.camera)
	return Data.fail("书签不存在")

func update_roads(args: Dictionary) -> Dictionary:
	var ready:=guard()
	if not ready.ok: return ready
	var value:=Data.resolve(editor._doc.map_meta); var graph: Dictionary=value.roads
	var original: Dictionary=graph.duplicate(true)
	if str(args.get("expected_token",""))!=Data.token(graph): return Data.fail("道路草案已变化，请重新读取 road_token 再修改")
	var nodes: Dictionary={}; var edges: Dictionary={}
	for item in graph.nodes: nodes[item.id]=item
	for item in graph.edges: edges[item.id]=item
	for kind in ["nodes","edges"]:
		var table: Dictionary=nodes if kind=="nodes" else edges
		var touched:={}
		for id in args.get("remove_"+kind,[]):
			if not table.has(id) or touched.has(id): return Data.fail("删除的道路 ID 不存在或重复")
			if table[id].get("locked",false) or table[id].get("hidden",false): return Data.fail("请先解锁并显示道路元素")
			touched[id]=true; table.erase(id)
		for entry in args.get(kind,[]):
			if touched.has(entry.id): return Data.fail("同次修改不能重复道路 ID")
			touched[entry.id]=true
			if table.has(entry.id) and (table[entry.id].get("locked",false) or table[entry.id].get("hidden",false)):
				var before: Dictionary=table[entry.id].duplicate(true); var after: Dictionary=entry.duplicate(true)
				for flag in ["locked","hidden"]: before.erase(flag); after.erase(flag)
				if kind=="edges": before.name=before.get("name",""); after.name=after.get("name","")
				if before!=after: return Data.fail("请先单独解锁并显示，再修改道路元素")
			table[entry.id]=entry.duplicate(true)
	# Locked or hidden incident edges also protect moving/removing their endpoint nodes.
	for node in graph.nodes:
		if not node.get("locked",false) and not node.get("hidden",false): continue
		for edge in edges.values():
			if node.id not in [edge.from,edge.to]: continue
			var existed:=false
			for old in graph.edges:
				if old.id==edge.id and old.from==edge.from and old.to==edge.to: existed=true; break
			if not existed: return Data.fail("请先解锁并显示连接节点，再增加连接线")
	for edge in graph.edges:
		if not edge.get("locked",false) and not edge.get("hidden",false): continue
		for id in [edge.from,edge.to]:
			var before: Dictionary={}
			for node in graph.nodes:
				if node.id==id: before=node; break
			if not nodes.has(id) or nodes[id].position!=before.position: return Data.fail("节点连接着锁定或隐藏的道路，请先解除保护")
	graph.nodes=nodes.values(); graph.edges=edges.values()
	for old in original.edges:
		if not old.has("bridge_ref"): continue
		if not edges.has(old.id): return Data.fail("桥梁连线需使用解除路网绑定操作删除")
		var before: Dictionary=old.duplicate(true); var after: Dictionary=edges[old.id].duplicate(true)
		for flag in ["locked","hidden","name"]: before.erase(flag); after.erase(flag)
		if before!=after: return Data.fail("桥梁连线由河道配方管理，请先解除路网绑定")
	var checked:=Data.analyze(graph)
	if not checked.ok: return checked
	var binding:=preload("res://scripts/world3d/road_bridges.gd").resolve(value)
	if not binding.ok: return binding
	var result:=commit(value)
	result.road_token=Data.token(graph); result.diagnostics=checked.diagnostics
	return result

func add_path(points: Array, width: float, kind: String) -> Dictionary:
	var value:=Data.resolve(editor._doc.map_meta); var nodes: Array=[]; var edges: Array=[]; var ids: Array=[]
	for p in points:
		var id:=""
		for node in value.roads.nodes+nodes:
			if Data.vec(node.position).distance_to(Data.vec(p))<.25:
				if node.get("locked",false) or node.get("hidden",false): return Data.fail("端点落在受保护的道路节点，请先解锁显示")
				id=node.id; break
		if id.is_empty():
			id="node_"+Crypto.new().generate_random_bytes(6).hex_encode(); nodes.append({"id":id,"position":p})
		ids.append(id)
	var ports:=preload("res://scripts/world3d/road_bridges.gd").resolve(value)
	if not ports.ok: return ports
	for i in ids.size()-1:
		var edge:={"id":"road_"+Crypto.new().generate_random_bytes(6).hex_encode(),"from":ids[i],"to":ids[i+1],"width_start":width,"width_end":width,"kind":kind,"name":"道路 %d"%(value.roads.edges.size()+i+1)}
		for port in ports.portals:
			if ids[i] in port.nodes: edge.width_start=minf(width,port.width)
			if ids[i+1] in port.nodes: edge.width_end=minf(width,port.width)
		edges.append(edge)
	return update_roads({"expected_token":Data.token(value.roads),"nodes":nodes,"edges":edges})

func begin_draw(width: float, height: float, kind: String) -> Dictionary:
	var ready:=guard()
	if not ready.ok: return ready
	draw_width=width; draw_height=height; draw_kind=kind; pending=[]; drawing=true; zone_draft={}
	scatter_draft=false
	waterway_draft=false
	bridge_draft=false
	fortification_draft=false
	if panel!=null: editor._dock_tabs.current_tab=panel.tab_index
	editor._status.text="点选道路节点 · Enter 提交 · Backspace 退一点 · Esc 取消；端点靠近已有节点会吸附"
	return {"ok":true}

func begin_zone(zone: Dictionary) -> Dictionary:
	var result:=begin_draw(1,float(zone.min_y),"ground")
	if result.ok:
		zone_draft=zone.duplicate(true)
		editor._status.text="点选区域边界（至少 3 点）· Enter 闭合提交 · Backspace 退一点 · Esc 取消"
	return result

func begin_scatter(height: float) -> Dictionary:
	var result:=begin_draw(1,height,"ground")
	if result.ok:
		scatter_draft=true
		editor._status.text="点选植被区域边界 · Enter 完成 · Backspace 退一点 · Esc 取消"
	return result

func begin_bridge(height: float) -> Dictionary:
	var result:=begin_draw(1,height,"bridge")
	if result.ok:
		bridge_draft=true
		editor._status.text="点选两个桥头 · Enter 确认 · Esc 取消；随后预览石桥"
	return result

func begin_waterway(height: float) -> Dictionary:
	var result:=begin_draw(1,height,"ground")
	if result.ok:
		waterway_draft=true
		editor._status.text="点选河道中心线 · Enter 完成 · Backspace 退一点 · Esc 取消"
	return result

func begin_fortification(height: float) -> Dictionary:
	var result:=begin_draw(1,height,"ground")
	if result.ok:
		fortification_draft=true
		editor._status.text="点选城墙中心线（环形模式选两个范围对角）· Enter 完成 · Backspace 退一点 · Esc 取消"
	return result

func finish_draw(cancel: bool = false) -> Dictionary:
	if not drag_node.is_empty(): finish_node_drag(true)
	drawing=false
	var result:={"ok":true}
	if not cancel:
		if bridge_draft:
			result=panel.bridge_panel.set_points(pending)
		elif fortification_draft:
			result=panel.fortification_panel.set_points(pending.map(func(p):return [p[0],p[2]]))
		elif waterway_draft:
			result=panel.waterway_panel.set_points(pending.map(func(p):return [p[0],p[2]]))
		elif scatter_draft:
			result=panel.scatter_panel.set_polygon(pending.map(func(p):return [p[0],p[2]]))
		elif not zone_draft.is_empty():
			var zone:=zone_draft.duplicate(true); zone.polygon=pending.map(func(p):return [p[0],p[2]])
			result=editor._roads.zones({"expected_token":JSON.stringify(data.get("zones",[])).sha256_text(),"zones":[zone]})
		elif pending.size()<2: result=Data.fail("至少点选两个道路节点")
		else: result=add_path(pending,draw_width,draw_kind)
	if result.ok or cancel: pending=[]; zone_draft={}; scatter_draft=false; waterway_draft=false; bridge_draft=false; fortification_draft=false
	else: drawing=true
	return result

func input(event: InputEvent) -> bool:
	if editor._playtest!=null and editor._playtest.active(): return false
	if drawing and panel!=null and editor._dock_tabs.current_tab!=panel.tab_index:
		finish_draw(true); return false
	if not drag_node.is_empty():
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: finish_node_drag(true); return true
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
			panel.report(finish_node_drag()); return true
		if event is InputEventMouseMotion:
			var screen: Vector2=event.position-editor._canvas.global_position
			if screen.distance_to(drag_screen)<3 and not drag_moved: return true
			var p:=Data.vec(drag_node.position)
			var hit: Variant=Plane(Vector3.UP,p.y).intersects_ray(editor._camera.project_ray_origin(screen),editor._camera.project_ray_normal(screen))
			if hit!=null:
				var position: Vector3=p+hit-drag_anchor
				if not event.alt_pressed and editor._snap>0: position.x=snappedf(position.x,editor._snap); position.z=snappedf(position.z,editor._snap)
				for node in data.roads.nodes:
					if node.id==drag_node.id: node.position=Data.xyz(position); analysis.nodes[node.id]=node
				for edge in data.roads.edges:
					if drag_node.id in [edge.from,edge.to]: analysis.paths[edge.id]=Data.samples(edge,analysis.nodes)
				drag_moved=true
			return true
		return event is InputEventKey or event is InputEventMouseButton
	if not drawing:
		if panel==null or editor._dock_tabs.current_tab!=panel.tab_index: return false
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and editor._canvas.get_global_rect().has_point(event.position):
			if overlay!=null and overlay.mini.visible and overlay.mini.get_global_rect().has_point(event.position): return false
			if panel.block_panel!=null and panel.block_panel.picking.button_pressed:
				if event.pressed: panel.block_panel.pick(event.position-editor._canvas.global_position)
				return true
			if event.pressed:
				var ready:=guard()
				if not ready.ok: panel.report(ready); return true
				var screen: Vector2=event.position-editor._canvas.global_position
				var best:=12.0; var found: Dictionary={}
				for node in data.roads.nodes:
					var p:=Data.vec(node.position)
					if node.get("hidden",false) or editor._camera.is_position_behind(p): continue
					var distance: float=editor._camera.unproject_position(p).distance_to(screen)
					if distance<best: best=distance; found=node
				if not found.is_empty():
					panel.select_node(found.id)
					if found.get("locked",false): panel.report(Data.fail("节点已锁定")); return true
					for edge in data.roads.edges:
						if found.id in [edge.from,edge.to] and (edge.get("locked",false) or edge.get("hidden",false)):
							panel.report(Data.fail("连接线段已锁定或隐藏，不能拖动此节点")); return true
					var hit: Variant=Plane(Vector3.UP,float(found.position[1])).intersects_ray(editor._camera.project_ray_origin(screen),editor._camera.project_ray_normal(screen))
					if hit!=null:
						drag_node=found.duplicate(true); drag_screen=screen; drag_anchor=hit; drag_moved=false
						drag_token=Data.token(Data.resolve(editor._doc.map_meta).roads)
			return true
		return false
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE:
			finish_draw(true)
		elif event.keycode==KEY_BACKSPACE:
			if not pending.is_empty(): pending.pop_back()
		elif event.keycode==KEY_ENTER:
			panel.report(finish_draw())
		return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and editor._canvas.get_global_rect().has_point(event.position):
		if overlay != null and overlay.mini.visible and overlay.mini.get_global_rect().has_point(event.position): return false
		if event.pressed:
			var screen: Vector2=event.position-editor._canvas.global_position
			var hit: Variant=Plane(Vector3.UP,draw_height).intersects_ray(editor._camera.project_ray_origin(screen),editor._camera.project_ray_normal(screen))
			if hit!=null:
				var closest:=14.0
				for node in data.roads.nodes:
					if not zone_draft.is_empty() or scatter_draft or waterway_draft or fortification_draft: break
					if node.get("hidden",false) or node.get("locked",false): continue
					var p:=Data.vec(node.position)
					if editor._camera.is_position_behind(p): continue
					var distance: float=editor._camera.unproject_position(p).distance_to(screen)
					if distance<closest: closest=distance; hit=p
				if pending.size()<64: pending.append(Data.xyz(hit))
		return true
	return false

func finish_node_drag(cancel: bool = false) -> Dictionary:
	var node: Dictionary=analysis.nodes.get(drag_node.get("id",""),{}).duplicate(true)
	var moved:=drag_moved
	drag_node={}; drag_moved=false
	var result:={"ok":true,"changed":false}
	if moved and not cancel: result=update_roads({"expected_token":drag_token,"nodes":[node]})
	if cancel or not moved or not result.ok: refresh()
	return result
