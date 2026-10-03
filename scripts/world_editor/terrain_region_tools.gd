extends RefCounted
const Data=preload("res://scripts/world3d/terrain_regions.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Commit=preload("res://scripts/world_editor/river_material_tools.gd")
static func material_index(materials: Array,definition: Dictionary) -> int:
	# Builtins use integers while saved JSON uses floats. Compare normalized data
	# so reusing white/checker after reopening cannot consume another slot.
	var normalized: Variant=JSON.parse_string(JSON.stringify(definition))
	for i in materials.size():
		if JSON.parse_string(JSON.stringify(materials[i]))==normalized: return i
	return -1
static func prepare(records: Array,args: Dictionary,library,editable: Callable,remove: bool=false) -> Dictionary:
	var schema:=Data.request_schema()
	if remove:
		schema.properties={"id":schema.properties.id,"terrain_ids":schema.properties.terrain_ids}; schema.required=["id","terrain_ids"]
	var error:=Data.S.validate(args,schema)
	if not error.is_empty(): return Paint.fail(error)
	if not str(args.id).is_valid_identifier(): return Paint.fail("区域 ID 需为字母/数字/下划线标识")
	var material: Dictionary={}
	if not remove:
		if not Data.polygon_valid(args.polygon): return Paint.fail("区域需为不自交且面积至少 1 平方米的多边形")
		material=library.find(args.material_id)
		if not Paint.material_valid(material) or material.color[3]!=1: return Paint.fail("请选择不透明 PBR 地表材质")
		for field in Paint.MAP_FIELDS:
			if not str(material.get(field,"")).is_empty() and Paint.texture(material,field)==null: return Paint.fail("区域贴图缺失、损坏或超过 4K")
	var replacements: Array=[]; var seen:={}; var work:=0
	for id in args.terrain_ids:
		if seen.has(id): return Paint.fail("地形 ID 重复")
		seen[id]=true
		var matches:=records.filter(func(r):return r.uuid==id)
		if matches.size()!=1 or not editable.call(matches[0]): return Paint.fail("地形不存在、锁定、隐藏或不在当前楼层；整笔未应用")
		var record: Dictionary=matches[0]
		if not record.has("terrain_mesh") or not Terrain.valid(record) or record.has("surface_paint"): return Paint.fail("区域绘制需要无手刷表面覆盖的可雕刻地形")
		if absf(record.rotation[0])>.001 or absf(record.rotation[2])>.001: return Paint.fail("区域绘制暂不支持 X/Z 倾斜地形")
		var next:=record.duplicate(true); var data: Dictionary=next.get("terrain_regions",{"materials":[],"regions":[]})
		var previous: Array=data.regions.filter(func(r):return r.id==args.id)
		if not previous.is_empty() and previous[0].has("furrows"): return Paint.fail("该区域已有垄沟；请先停用垄沟再修改范围或删除区域，避免意外覆盖农田几何")
		var insertion: int=data.regions.find(previous[0]) if not previous.is_empty() else data.regions.size()
		data.regions=data.regions.filter(func(r):return r.id!=args.id)
		if not remove:
			var local: Array=[]; var inverse:=Terrain.transform(record).affine_inverse()
			for point in args.polygon:
				var p:=inverse*Vector3(point[0],record.position[1],point[1]); local.append([p.x,p.z])
			var polygon:=Data.points({"polygon":local}); var span:=Vector2(record.size[0],record.size[2])
			# Keep entire polygons, including the feather outside this patch. Clipping
			# at a chunk edge would incorrectly create a new material boundary there.
			if Data.bounds(polygon).grow(args.get("feather",4.)).intersects(Rect2(-span*.5,span)):
				var layer:=material_index(data.materials,material)
				if layer<0:
					Data.compact(data); layer=material_index(data.materials,material)
					if layer<0: layer=data.materials.size(); data.materials.append(material.duplicate(true))
				data.regions.insert(mini(insertion,data.regions.size()),{"id":args.id,"polygon":local,"feather":args.get("feather",4.),"opacity":args.get("opacity",1.),"layer":layer})
		if data.regions.is_empty(): next.erase("terrain_regions")
		else:
			Data.compact(data); next.terrain_regions=data
			if data.materials.size()>2: return Paint.fail("每块最多 2 种区域覆盖材质；可先删除不用的区域")
			if not Data.valid(next): return Paint.fail("区域数据无效或超过每块 32 区域、256 顶点")
		if not Paint.valid(next): return Paint.fail("区域或底材无效（地表底材需不透明）")
		if next!=record:
			work+=Data.work(next)
			if work>8000000: return Paint.fail("区域遮罩计算量过大，请减少同时修改的地形或多边形顶点；整笔未应用")
			replacements.append(next)
	return {"ok":true,"changed":not replacements.is_empty(),"records":replacements}
static func apply(editor: Node3D,args: Dictionary,remove: bool=false) -> Dictionary:
	var guard: Dictionary=editor._gameplay.guard()
	if not guard.ok: return guard
	return Commit.commit(editor,prepare(editor._doc.records,args,editor._material_tool.library,editor._record_editable,remove))
