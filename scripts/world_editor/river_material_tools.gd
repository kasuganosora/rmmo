extends RefCounted
const Data=preload("res://scripts/world3d/river_material_data.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
static func fail(message: String) -> Dictionary: return {"ok":false,"error":message}
static func transition(args: Dictionary,library) -> Dictionary:
	var config:=Data.TRANSITION_DEFAULTS.duplicate()
	for key in config:
		if args.has(key): config[key]=args[key]
	if config.transition_width>0:
		var material: Dictionary=library.find(args.get("transition_material_id",Data.TRANSITION_MATERIAL))
		if not Paint.material_valid(material) or material.get("color",[1,1,1,0])[3]!=1: return fail("请选择不透明的土层 / 碎石过渡材质")
		for field in Paint.MAP_FIELDS:
			if not str(material.get(field,"")).is_empty() and Paint.texture(material,field)==null: return fail("过渡材质贴图缺失、损坏或超过 4K")
		config.transition_material=material.duplicate(true)
	return {"ok":true,"config":config}

static func prepare(records: Array, args: Dictionary, library, editable: Callable) -> Dictionary:
	var error:=Data.S.validate(args,Data.request_schema())
	if not error.is_empty(): return fail(error)
	var terrain_ids: Array=args.get("terrain_ids",[]); var water_ids: Array=args.get("water_ids",[])
	var bank_ids: Array=args.get("bank_ids",[])
	if terrain_ids.is_empty() and water_ids.is_empty() and bank_ids.is_empty(): return fail("请选择河床地形、河流水面或水渠护岸")
	var ids: Array=terrain_ids+water_ids+bank_ids; var seen:={}; var config:=Data.DEFAULTS.duplicate(true)
	for key in config:
		if args.has(key): config[key]=args[key]
	if not Data.ordered(config): return fail("岸上高度、岩石深度及陡坡角度的结束值必须大于起始值")
	var enabled: bool=args.get("enabled",true)
	var sand: Dictionary={}; var rock: Dictionary={}
	var blend: Dictionary={}
	if enabled and not terrain_ids.is_empty():
		if config.bank_profile=="natural":
			var resolved:=transition(args,library)
			if not resolved.ok: return resolved
			blend=resolved.config
		sand=library.find(args.get("sand_material_id","")); rock=library.find(args.get("rock_material_id",""))
		for value in [sand,rock]:
			if not Paint.material_valid(value) or value.get("color",[1,1,1,0])[3]!=1: return fail("请选择不透明的沙地与岩石 PBR 材质")
			for field in Paint.MAP_FIELDS:
				if not str(value.get(field,"")).is_empty() and Paint.texture(value,field)==null: return fail("沙地 / 岩石贴图缺失、损坏或超过 4K")
	var replacements: Array=[]
	for id in ids:
		if seen.has(id): return fail("地形和水面 ID 不能重复")
		seen[id]=true
		var matches: Array=records.filter(func(r):return r.uuid==id)
		if matches.size()!=1 or not editable.call(matches[0]): return fail("目标不存在、隐藏、锁定或不在当前楼层")
		var record: Dictionary=matches[0]; var next:=record.duplicate(true)
		var field:="terrain_depth_blend" if terrain_ids.has(id) else ("water_depth_effect" if water_ids.has(id) else "bank_wetness")
		if terrain_ids.has(id):
			if not record.has("terrain_mesh"): return fail("河床目标必须是可雕刻地形")
			if enabled and record.has("surface_paint"): return fail("请先清除河床手刷表面，避免渐变覆盖手工材质")
			if enabled and record.has("terrain_slope_blend"): return fail("请先停用独立坡度材质；自然河岸模式已包含坡度露岩")
			if enabled:
				next[field]={"water_level":config.water_level,"shore_start":config.shore_start,"shore_end":config.shore_end,"rock_start":config.rock_start,"rock_end":config.rock_end,"sand_material":sand.duplicate(true),"rock_material":rock.duplicate(true)}
				for key in ["bank_profile","steep_start","steep_end"]: next[field][key]=config[key]
				# Opt-in for existing maps; retain the previous dry appearance when absent.
				if args.get("wet_darkening",0)>0:
					next[field].wet_height=config.wet_height
					next[field].wet_darkening=args.wet_darkening
				next[field].merge(blend)
		elif bank_ids.has(id):
			if not Data.bank_target(record): return fail("护岸仅支持普通方块或河道岸/底网格；不能将道路、建筑或水面作为护岸")
			if enabled: next[field]={"water_level":config.water_level,"wet_height":config.wet_height}
		else:
			if not record.has("channel_mesh") or record.get("surface_id")!="water": return fail("水面目标必须是河道水面")
			if enabled:
				if absf(record.rotation[0])>.0001 or absf(record.rotation[2])>.0001 or Vector2(record.channel_mesh.get("grade",[0,0])[0],record.channel_mesh.get("grade",[0,0])[1]).length()>.0001: return fail("深浅水效果需要水平水面")
				if (not terrain_ids.is_empty() or not bank_ids.is_empty()) and absf(record.position[1]+record.size[1]*.5-float(config.water_level))>.01: return fail("河床/护岸水位参数必须与所选水面实际标高一致")
				next[field]={"absorption":config.absorption,"shallow_color":config.shallow_color,"deep_color":config.deep_color}
		if not enabled: next.erase(field)
		if not Paint.valid(next) or not Paint.missing([next]).is_empty(): return fail("渐变材质记录或资源依赖无效")
		if next!=record: replacements.append(next)
	return {"ok":true,"records":replacements,"changed":not replacements.is_empty()}

static func apply(editor: Node3D, args: Dictionary) -> Dictionary:
	var guard: Dictionary=editor._gameplay.guard()
	if not guard.ok: return guard
	var result:=prepare(editor._doc.records,args,editor._material_tool.library,editor._record_editable)
	return commit(editor,result)

static func prepare_slope(records: Array,args: Dictionary,library,editable: Callable) -> Dictionary:
	var error:=Data.S.validate(args,Data.slope_schema())
	if not error.is_empty(): return fail(error)
	if args.terrain_ids.is_empty(): return fail("请选择至少一块可雕刻地形")
	var enabled: bool=args.get("enabled",true)
	var start: float=args.get("steep_start",40.0); var end: float=args.get("steep_end",65.0)
	if end<=start+.001: return fail("完全露岩角度必须大于开始露岩角度")
	var rock: Dictionary={}
	var blend: Dictionary={}
	if enabled:
		var resolved:=transition(args,library)
		if not resolved.ok: return resolved
		blend=resolved.config
		rock=library.find(args.get("rock_material_id",""))
		if not Paint.material_valid(rock) or rock.get("color",[1,1,1,0])[3]!=1: return fail("请选择不透明岩石 PBR 材质")
		for field in Paint.MAP_FIELDS:
			if not str(rock.get(field,"")).is_empty() and Paint.texture(rock,field)==null: return fail("岩石贴图缺失、损坏或超过 4K")
	var replacements: Array=[]; var seen:={}
	for id in args.terrain_ids:
		if seen.has(id): return fail("地形 ID 不能重复")
		seen[id]=true
		var matches: Array=records.filter(func(r):return r.uuid==id)
		if matches.size()!=1 or not editable.call(matches[0]): return fail("地形不存在、隐藏、锁定或不在当前楼层")
		var record: Dictionary=matches[0]; var next:=record.duplicate(true)
		if not record.has("terrain_mesh"): return fail("坡度材质仅支持可雕刻地形")
		if enabled:
			if record.has("surface_paint") or record.has("terrain_depth_blend"): return fail("请先停用河床渐变或清除手刷表面；自然河岸已包含坡度露岩")
			next.terrain_slope_blend={"rock_material":rock.duplicate(true),"steep_start":start,"steep_end":end}
			next.terrain_slope_blend.merge(blend)
		else: next.erase("terrain_slope_blend")
		if not Paint.valid(next) or not Paint.missing([next]).is_empty(): return fail("地形材质或资源依赖无效")
		if next!=record: replacements.append(next)
	return {"ok":true,"changed":not replacements.is_empty(),"records":replacements}

static func apply_slope(editor: Node3D,args: Dictionary) -> Dictionary:
	var guard: Dictionary=editor._gameplay.guard()
	if not guard.ok: return guard
	return commit(editor,prepare_slope(editor._doc.records,args,editor._material_tool.library,editor._record_editable))

static func commit(editor: Node3D,result: Dictionary) -> Dictionary:
	if not result.ok or not result.changed: return result
	editor._doc.checkpoint()
	var ids: Array[String]=[]
	for replacement in result.records:
		var old: Dictionary=editor._doc._find(replacement.uuid)
		editor._doc.records[editor._doc.records.find(old)]=replacement; ids.append(replacement.uuid)
	editor._dirty=true; editor._refresh_records(ids)
	if editor._terrain_panel!=null: editor._terrain_panel.refresh()
	return {"ok":true,"changed":true,"changed_ids":ids}
