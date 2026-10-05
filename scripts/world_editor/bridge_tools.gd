extends RefCounted
const D=preload("res://scripts/world3d/bridge_data.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var editor: Node3D
var library=preload("res://scripts/world_editor/bridge_library.gd").new()
var preview_node: Node3D
func catalog() -> Dictionary: return {"ok":true,"prefabs":library.entries()}
static func make_record(args: Dictionary,prefab: Dictionary) -> Dictionary:
	var a:=Data.vec(args.start); var b:=Data.vec(args.end); var length_: float=Vector2(b.x-a.x,b.z-a.z).length()
	var recipe: Dictionary=prefab.recipe.duplicate(true)
	var count:=int(args.get("arches",0))
	if count==0: count=maxi(1,ceili((length_-2+recipe.pier_width)/(recipe.max_span+recipe.pier_width)))
	var data:={"version":1,"prefab_id":prefab.id,"length":length_,"width":float(args.get("width",6)),"depth":float(args.get("depth",4)),"camber":float(args.get("camber",0)),"arches":count,"recipe":recipe}
	var position:=a.lerp(b,.5)-Vector3.UP*D.deck_local_y(data)
	var dimensions:=D.dimensions(data)
	var path: String=prefab.get("asset_path",preload("res://scripts/world3d/map_paths.gd").external_root().path_join("packs/default/assets/bridges/medieval_stone/stone_"+recipe.style+".glb"))
	return {"uuid":args.id,"kind":"asset","asset_path":path,"surface_id":"bridge_deck","collision":"walk","position":Data.xyz(position),"rotation":[0,rad_to_deg(-atan2(b.z-a.z,b.x-a.x)),0],"size":[1,1,1],"bounds_position":[-dimensions.x*.5,-data.depth,-dimensions.z*.5],"bounds_size":Data.xyz(dimensions),"editor_name":args.get("name",prefab.name),"bridge_mesh":data,"bridge_materials":prefab.get("materials",{}).duplicate(true)}
func prepare(args: Dictionary,binding_update:=false) -> Dictionary:
	var error:=D.S.validate(args,D.request_schema())
	if not error.is_empty(): return Data.fail(error)
	if args.has("road_edge_id"): return preload("res://scripts/world_editor/bridge_road_tools.gd").prepare(editor,args)
	if not binding_update:
		for e in Data.resolve(editor._doc.map_meta).roads.edges:
			if e.get("stone_bridge",{}).get("id","")==args.id: return Data.fail("这座桥已接入道路，请带 road_edge_id 或从道路桥型入口修改")
	if args.id.is_empty() or not args.id.is_valid_identifier(): return Data.fail("桥梁 ID 必须为有效标识符")
	if absf(args.start[1]-args.end[1])>.01: return Data.fail("当前石桥的两端须同高，请先整平桥头或增设引道")
	var old: Dictionary=editor._doc._find(args.id)
	if old.get("prefab_locked",false):return Data.fail("固定桥梁预制件不能再修改跨度、拱孔或材质；请新建桥梁")
	if not old.is_empty():
		if not old.has("bridge_mesh") or not editor._record_editable(old): return Data.fail("ID 被其他物件占用，或桥梁已隐藏 / 锁定 / 隔层")
		if editor._selection_tools.members(args.id).is_empty(): return Data.fail("桥梁所在组合含受保护物件")
		for region in editor._waterways.regions():
			if region.parts.any(func(p):return p.id==args.id): return Data.fail("此桥属于河道配方，请在河道面板中修改")
		if old.has("surface_paint") or old.has("event_template") or old.has("event"): return Data.fail("桥梁有手工刷面或事件，请先处理后再重生成")
	var preset_id: String=args.get("prefab_id",old.get("bridge_mesh",{}).get("prefab_id","stone_segmental"))
	var prefab: Dictionary=library.find(preset_id)
	if prefab.is_empty(): return Data.fail("桥梁预制件不存在："+preset_id)
	var resolved:=args.duplicate(true)
	for key in ["width","depth","camber"]:
		if not resolved.has(key) and old.has("bridge_mesh"): resolved[key]=old.bridge_mesh[key]
	var record:=make_record(resolved,prefab)
	if not old.is_empty():
		record=old.merged(record,true)
		if not args.has("name"): record.editor_name=old.get("editor_name",prefab.name)
	if not D.valid(record): return Data.fail("跨度须为 6～120 米，拱孔 2 米以上；拱高须保证坡度不超过 15%（最大为跨度 × 0.0477）")
	if preload("res://scripts/world3d/bridge_mesh.gd").kit(record.asset_path).is_empty(): return Data.fail("Blender 桥梁模块库缺失或结构无效")
	if not editor._authoring.Settings.contains(record,editor._authoring.settings): return Data.fail("桥梁超出当前隔离楼层")
	var defaults:=preload("res://scripts/world3d/bridge_data.gd").default_materials()
	if not old.is_empty() and preset_id==old.bridge_mesh.prefab_id: record.bridge_materials=old.bridge_materials.duplicate(true)
	for role in defaults:
		if args.has(role+"_material_id"):
			var id: String=args[role+"_material_id"]; var material: Dictionary=editor._material_tool.library.find(id)
			if material.is_empty(): return Data.fail("桥梁材质不存在："+id)
			record.bridge_materials[role]=material
		elif not record.bridge_materials.has(role):
			var material: Dictionary=editor._material_tool.library.find(defaults[role])
			if material.is_empty(): return Data.fail("默认石桥材质缺失："+str(defaults[role]))
			record.bridge_materials[role]=material
	if not Paint.valid(record) or not Paint.missing([record]).is_empty(): return Data.fail("桥梁材质依赖缺失")
	var navigation:=preload("res://scripts/world_editor/bridge_clearance.gd").fit(record,editor._doc.records,args.get("auto_clearance",true))
	if not navigation.ok: return navigation
	# Ground/river surfaces are support. All other objects, including hidden ones,
	# are checked against the entire bridge and its walkable clearance envelope.
	var shape:=Foot.record_shape(record); shape.bounds.size.y+=3
	var support: Array=[]
	for r in editor._doc.records:
		if r.uuid==args.id: continue
		if r.get("surface_id")=="water": continue
		var ground: bool=r.has("terrain_mesh") or r.has("road_mesh") or (r.get("kind")=="box" and r.get("surface_id") in ["ground","grass","dirt","sand","stone","river_bank","river_bed"])
		if ground:
			var bounds: AABB=Foot.record_shape(r).bounds
			if Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z).intersects(Rect2(shape.bounds.position.x,shape.bounds.position.z,shape.bounds.size.x,shape.bounds.size.z),true): support.append(r)
			continue
		if Foot.batches_overlap([shape],Foot.record_shapes(r)): return Data.fail("桥梁与现有物件冲突："+str(r.uuid))
	var transform:=Transform3D(Basis.from_euler(Data.vec(record.rotation)*PI/180),Data.vec(record.position))
	var d: Dictionary=record.bridge_mesh
	for end in [-1,1]:
		for z in [-d.width*.5+.6,0,d.width*.5-.6]:
			var p: Vector3=transform*Vector3(end*(d.length*.5+.06),0,z)
			var h:=ground_height(support,p)
			if not is_finite(h) or absf(h-p.y)>.12: return Data.fail("两端桥头的通行宽度必须落在同高地面或道路上，不能悬空")
	for i in ceili(d.length/.75)+1:
		var x: float=lerpf(-d.length*.5,d.length*.5,i/float(ceili(d.length/.75)))
		for z in [-d.width*.5+.6,0,d.width*.5-.6]:
			var p: Vector3=transform*Vector3(x,preload("res://scripts/world3d/bridge_mesh.gd").height_at(x,d),z)
			var h:=ground_height(support,p)
			if is_finite(h) and h>p.y+.08: return Data.fail("地形或既有路面穿过桥面，请调整桥头高度或先整平")
	var token:=Data.token([record,editor._doc.records,editor._doc.map_meta,editor._authoring.settings])
	if args.has("plan_token") and args.plan_token!=token: return Data.fail("桥梁预览已过期，请重新预览")
	return {"ok":true,"record":record,"plan_token":token,"navigation":navigation}
static func ground_height(records: Array,p: Vector3) -> float:
	var height:=-INF
	for r in records:
		var transform:=Transform3D(Basis.from_euler(Data.vec(r.rotation)*PI/180),Data.vec(r.position)); var local: Vector3=transform.affine_inverse()*p
		if r.has("terrain_mesh"):
			var h:=preload("res://scripts/world3d/terrain_surface.gd").sample(r,local)
			if is_finite(h): height=maxf(height,(transform*Vector3(local.x,h,local.z)).y)
		elif r.has("road_mesh") or r.has("channel_mesh"):
			var polys: Array=preload("res://scripts/world3d/road_surface.gd").local_polygons(r) if r.has("road_mesh") else preload("res://scripts/world3d/channel_surface.gd").local_polygons(r)
			for poly in polys:
				if Geometry2D.is_point_in_polygon(Vector2(local.x,local.z),PackedVector2Array(poly.map(func(v):return Vector2(v.x,v.z)))):
					var plane:=Plane(poly[0],poly[1],poly[2]); var hit: Variant=plane.intersects_ray(Vector3(local.x,100000,local.z),Vector3.DOWN)
					if hit!=null: height=maxf(height,(transform*hit).y)
		elif absf(local.x)<=r.size[0]*.5+.001 and absf(local.z)<=r.size[2]*.5+.001:
			height=maxf(height,(transform*Vector3(local.x,r.size[1]*.5,local.z)).y)
	return height
func summary(args: Dictionary) -> Dictionary:
	var p:=prepare(args)
	if not p.ok: return p
	return {"ok":true,"plan_token":p.plan_token,"id":p.record.uuid,"prefab_id":p.record.bridge_mesh.prefab_id,"arches":p.record.bridge_mesh.arches,"length":p.record.bridge_mesh.length,"camber":p.record.bridge_mesh.camber,"max_grade":p.record.bridge_mesh.camber*PI/p.record.bridge_mesh.length,"clear_width":p.record.bridge_mesh.width-1.16,"mesh_instances":1,"material_surfaces":3,"road_edge_id":p.get("road_edge_id",""),"trimmed_roads":p.get("trimmed_roads",[]),"navigation":p.navigation}
func show_preview(args: Dictionary) -> Dictionary:
	clear_preview(); var p:=prepare(args)
	if not p.ok: return p
	preview_node=editor._doc._asset(p.record); editor.add_child(preview_node)
	return summary(args)
func clear_preview() -> void:
	if is_instance_valid(preview_node): preview_node.queue_free()
	preview_node=null
func generate(args: Dictionary) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var p:=prepare(args)
	if not p.ok: return p
	var old: Dictionary=editor._doc._find(args.id)
	if Data.token(old)==Data.token(p.record) and (not p.has("layout") or Data.token(p.layout)==Data.token(Data.resolve(editor._doc.map_meta)) and p.trimmed_roads.is_empty()): return {"ok":true,"changed":false,"id":args.id}
	var frozen:=preload("res://scripts/world3d/structure_prefab.gd").bridge(p.record)
	if not frozen.ok:return frozen
	p.record=frozen.record
	if p.has("layout"):
		for i in p.records.size():
			if p.records[i].uuid==args.id:p.records[i]=p.record
		preload("res://scripts/world3d/structure_prefab.gd").refresh_bindings({"editor_layout":p.layout},p.records)
	clear_preview(); editor._doc.checkpoint_recovery(); editor._doc.records=editor._doc.records.filter(func(r):return r.uuid!=args.id); editor._doc.records.append(p.record)
	if p.has("layout"): editor._doc.records=p.records; editor._doc.map_meta.editor_layout=p.layout
	editor._dirty=true
	var changed: Array[String]=[str(args.id)]
	for id in p.get("trimmed_roads",[]): changed.append(str(id))
	# A bridge edit must not rebuild all 49 terrain patches in a kilometre-scale town.
	editor._refresh_records(changed); editor._city.refresh(); editor._selection_tools.refresh(); editor._object_list.refresh(); editor._refresh_selection()
	return {"ok":true,"changed":true,"id":args.id,"arches":p.record.bridge_mesh.arches}
func save_prefab(id: String,label: String) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	return library.save(editor._doc._find(id),label)

func bake(id:String)->Dictionary:
	var ready:Dictionary=editor._city.guard()
	if not ready.ok:return ready
	var old:Dictionary=editor._doc._find(id)
	if not old.has("bridge_mesh") or not editor._record_editable(old) or editor._selection_tools.members(id).is_empty():return Data.fail("桥梁不存在或受保护")
	for region in editor._waterways.regions():
		if region.parts.any(func(p):return p.id==id):
			var owner:Dictionary=editor._waterways.owned(region)
			if not owner.ok:return owner
	for edge in Data.resolve(editor._doc.map_meta).roads.edges:
		if edge.get("stone_bridge",{}).get("id","")==id:
			if edge.get("locked",false) or edge.get("hidden",false) or edge.stone_bridge.signature!=Data.token(old):return Data.fail("桥梁道路受保护或桥梁已被手改")
			for node in Data.resolve(editor._doc.map_meta).roads.nodes:
				if node.id in [edge.from,edge.to] and (node.get("locked",false) or node.get("hidden",false)):return Data.fail("桥头道路节点受保护")
	var frozen:=preload("res://scripts/world3d/structure_prefab.gd").bridge(old)
	if not frozen.ok:return frozen
	editor._doc.checkpoint_recovery()
	for i in editor._doc.records.size():
		if editor._doc.records[i].uuid==id:editor._doc.records[i]=frozen.record
	preload("res://scripts/world3d/structure_prefab.gd").refresh_bindings(editor._doc.map_meta,editor._doc.records)
	editor._dirty=true;editor._rebuild();return {"ok":true,"id":id,"component_count":1}
