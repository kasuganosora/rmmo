extends "res://tools/review_native_migration.gd"
## Narrow visual/renderer contract for the three migrated trees. The source arm
## writes a frozen camera recipe; the native arm reopens the actual publication.
## Each threshold side compares the normal scene against a forced-single-LOD
## control and a no-LOD negative control. Run only via private desktop.
const EPSILON:=0.25
const LOD_WINDOWS:=[[0.0,35.0],[35.0,85.0],[85.0,0.0]]
const DISTANCES:=[34.75,35.25,84.75,85.25]
const SELECTED:=[0,1,1,2]
const VIEW_NAMES:=["near","medium","far","detail"]
var lod_nodes:Array[MeshInstance3D]=[]
var lod_centre:=Vector3.ZERO

static func match_lod_window(begin:float,end:float)->int:
	for slot:int in LOD_WINDOWS.size():
		if is_equal_approx(begin,LOD_WINDOWS[slot][0]) and is_equal_approx(end,LOD_WINDOWS[slot][1]):return slot
	return -1

static func threshold_eye(centre:Vector3,index:int)->Vector3:
	if index<0 or index>=DISTANCES.size():return Vector3(INF,INF,INF)
	return centre+Vector3(1,.32,1.6).normalized()*DISTANCES[index]

func _arguments()->bool:
	if not super._arguments():return false
	if not check(mode in ["source","native"] and features.is_empty(),"LOD review requires source/native and the fixed day recipe without receiver features"):return false
	return true

func _code_identity()->Dictionary:
	var result:Dictionary=super._code_identity()
	result["res://tools/test_native_migration_lod_gpu.gd"]=FileAccess.get_sha256("res://tools/test_native_migration_lod_gpu.gd")
	return result

func _capture_recipe()->Dictionary:
	var result:Dictionary=super._capture_recipe()
	result.lod_scope="three tiled authored mesh ranges; shared world custom AABB centre; zero margins; disabled fade; non-LOD meshes remain visible"
	result.lod_distances=DISTANCES.duplicate();result.lod_windows=LOD_WINDOWS.duplicate(true)
	result.lod_expected=SELECTED.duplicate();result.lod_epsilon=EPSILON
	result.lod_controls=["normal authored ranges","force only expected member without range","hide all ranged members"]
	return result

func _local_to_review(node:Node)->Transform3D:
	var transform_:=Transform3D.IDENTITY;var current:Node=node
	while current!=null:
		if current is Node3D:transform_=current.transform*transform_
		if current==reviewed_scene:return transform_
		current=current.get_parent()
	return Transform3D.IDENTITY

func _layout()->bool:
	lod_nodes.clear();lod_centre=Vector3.ZERO
	var candidates:Array=[];gather(reviewed_scene,candidates)
	var slots:Array=[null,null,null]
	for node:Node in candidates:
		if node is GeometryInstance3D and not node is MeshInstance3D and (node.visibility_range_begin!=0.0 or node.visibility_range_end!=0.0):
			return check(false,"unsupported ranged non-mesh geometry")
		if not node is MeshInstance3D or node.mesh==null:continue
		var extra:Variant=node.get_meta("extras",{})
		if not extra is Dictionary or not extra.has("rmmo_visibility_range"):
			if node.visibility_range_begin!=0.0 or node.visibility_range_end!=0.0:return check(false,"unsupported untagged ranged mesh")
			continue
		var mesh:MeshInstance3D=node
		if not check(mesh.visible and mesh.custom_aabb.size.x>0.0 and mesh.custom_aabb.size.y>0.0 and mesh.custom_aabb.size.z>0.0,"ranged LOD mesh is visible with nonempty custom AABB"):return false
		if not check(mesh.visibility_range_begin_margin==0.0 and mesh.visibility_range_end_margin==0.0 and mesh.visibility_range_fade_mode==GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED and mesh.visibility_parent==NodePath(""),"LOD has zero margins, disabled fade and no visibility parent"):return false
		var parent:Node=mesh.get_parent()
		while parent!=null:
			if parent is Node3D and not check(parent.visible,"LOD ancestors are visible"):return false
			if parent==reviewed_scene:break
			parent=parent.get_parent()
		var index:=match_lod_window(mesh.visibility_range_begin,mesh.visibility_range_end)
		if not check(index>=0 and slots[index]==null,"each ranged mesh occupies one supported 35/85 interval"):return false
		slots[index]=mesh
		var centre:Vector3=_local_to_review(mesh)*mesh.custom_aabb.get_center()
		if lod_nodes.is_empty():lod_centre=centre
		elif not check(centre.is_equal_approx(lod_centre),"all LOD custom AABB centres coincide in review world"):return false
		lod_nodes.append(mesh)
	if not check(lod_nodes.size()==3 and slots.all(func(value):return value!=null),"exactly three complete supported LOD intervals"):return false
	lod_nodes.assign(slots)
	report.lod_layout={"scope":"three ranged meshes with equal world AABB centre; permanent meshes are not hidden","centre":vec(lod_centre),"windows":LOD_WINDOWS,"paths":lod_nodes.map(func(node):return str(reviewed_scene.get_path_to(node)))}
	return true

func _source_camera_packet(_bounds:AABB)->Dictionary:
	if not _layout():return {}
	var views:Array=[]
	for index:int in DISTANCES.size():
		views.append({"name":VIEW_NAMES[index],"eye":vec(threshold_eye(lod_centre,index)),"aim":vec(lod_centre),"fov":38.0,"projection":"perspective"})
	return {"version":1,"source_sha256":source_sha,"recipe":recipe,"views":views,"receiver":{}}

func _views()->Array:
	var views:Array=super._views()
	if views.is_empty() or not _layout():return []
	var expected:Dictionary=_source_camera_packet(scene_bounds(reviewed_scene))
	# The frozen camera is read from JSON. Compare through that same numeric
	# transport, without an epsilon that could hide a changed threshold camera.
	var transported:Variant=JSON.parse_string(JSON.stringify(expected.get("views",[]),"  ",true,true))
	if not check(not expected.is_empty() and Contract.same(views,transported),"same AABB-centred threshold cameras match the source arm"):return []
	return views

func _wait_frame_capture(camera:Camera3D,view:Dictionary,winds:Array,velocity:Vector3,wind_time:float)->Image:
	camera.position=vector(view.eye);camera.fov=float(view.fov);camera.look_at(vector(view.aim))
	for material:ShaderMaterial in winds:material.set_shader_parameter("wind_velocity",velocity);material.set_shader_parameter("wind_time",wind_time)
	for frame:int in 8:await process_frame;await RenderingServer.frame_post_draw
	if finished:return null
	return review_viewport.get_texture().get_image()

func _capture_control(image:Image,path:String)->Dictionary:
	if not check(image!=null and image.save_png(path)==OK,"capture LOD control "+path.get_file()):return {}
	var rid:=review_viewport.get_viewport_rid()
	return {"path":path,"sha256":FileAccess.get_sha256(path),"pixels":normalized_image(image),"draw_calls":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),"rendered_primitives":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)}

func _render(views:Array)->void:
	await super._render(views)
	if finished or not report.failures.is_empty():return
	var camera:Camera3D
	for child:Node in review_viewport.get_children():
		if child is Camera3D:camera=child;break
	if not check(camera!=null,"review viewport retains the fixed camera"):return
	var winds:Array[ShaderMaterial]=[]
	var all_nodes:Array=[];gather(reviewed_scene,all_nodes)
	for node:Node in all_nodes:
		if not node is MeshInstance3D or node.mesh==null:continue
		var extra:Variant=node.get_meta("extras",{})
		if not extra is Dictionary:continue
		var wind:Variant=extra.get("rmmo_wind",{})
		if not wind is Dictionary or wind.is_empty():continue
		var config:Dictionary=WindResponse.defaults().merged(wind,true)
		if config.profile=="off":continue
		for slot:int in node.mesh.get_surface_count():
			var material:Material=node.get_active_material(slot)
			if material is ShaderMaterial:winds.append(material)
	var poses:Array=[{"name":"still","velocity":Vector3.ZERO,"time":0.0}]
	if not winds.is_empty():poses.append_array([{"name":"wind_t1","velocity":Vector3(7,0,3),"time":1.0},{"name":"wind_t4","velocity":Vector3(7,0,3),"time":4.0}])
	var baseline:Dictionary={}
	for item:Dictionary in report.screenshots:baseline[item.name]=item
	var saved:Array=[]
	for node:MeshInstance3D in lod_nodes:saved.append({"visible":node.visible,"begin":node.visibility_range_begin,"end":node.visibility_range_end})
	report.lod_controls=[]
	for index:int in views.size():
		var selected:int=SELECTED[index];var view:Dictionary=views[index]
		for slot:int in lod_nodes.size():
			lod_nodes[slot].visible=slot==selected
			if slot==selected:lod_nodes[slot].visibility_range_begin=0.0;lod_nodes[slot].visibility_range_end=0.0
		for pose:Dictionary in poses:
			var image:Image=await _wait_frame_capture(camera,view,winds,pose.velocity,pose.time)
			if finished:return
			var name_:String="day_"+str(view.name)+"_"+str(pose.name)+".png"
			var expected:Dictionary=baseline.get(name_,{})
			var actual:=_capture_control(image,out.path_join(mode).path_join("forced_"+name_))
			if actual.is_empty():continue
			var same_pixels:bool=expected.get("pixels",{}).get("normalized_pixels_sha256","")==actual.pixels.get("normalized_pixels_sha256","")
			var same_draw:bool=expected.get("draw_calls",-1)==actual.draw_calls and expected.get("rendered_primitives",-1)==actual.rendered_primitives
			check(not expected.is_empty() and same_pixels and same_draw,"normal and forced single LOD agree: "+name_)
			report.lod_controls.append({"view":view.name,"distance":DISTANCES[index],"selected":selected,"pose":pose.name,"normal":expected,"forced":actual,"pixels_equal":same_pixels,"render_counts_equal":same_draw})
		for node:MeshInstance3D in lod_nodes:node.visible=false
		var empty_image:Image=await _wait_frame_capture(camera,view,winds,Vector3.ZERO,0.0)
		if finished:return
		var negative:=_capture_control(empty_image,out.path_join(mode).path_join("no_lod_"+str(view.name)+".png"))
		var still:Dictionary=baseline.get("day_"+str(view.name)+"_still.png",{})
		if not negative.is_empty():
			check(not still.is_empty() and (int(still.get("rendered_primitives",0))>int(negative.rendered_primitives) or int(still.get("draw_calls",0))>int(negative.draw_calls)),"negative control proves a ranged LOD rendered: "+str(view.name))
			report.lod_controls.append({"view":view.name,"distance":DISTANCES[index],"selected":"none","pose":"still","normal":still,"no_lod":negative})
		for slot:int in lod_nodes.size():
			lod_nodes[slot].visible=saved[slot].visible;lod_nodes[slot].visibility_range_begin=saved[slot].begin;lod_nodes[slot].visibility_range_end=saved[slot].end
	check(report.lod_controls.size()==views.size()*(poses.size()+1),"every boundary side has paired and negative control evidence")
