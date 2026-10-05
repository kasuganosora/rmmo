extends RefCounted
const Data=preload("res://scripts/world3d/city_layout.gd")
const F=preload("res://scripts/world3d/fortification_data.gd")
const Spacing=preload("res://scripts/world3d/fortification_spacing.gd")
const Plan=preload("res://scripts/world3d/fortification_plan.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Scatter=preload("res://scripts/world3d/vegetation_scatter.gd")
var editor: Node3D
var overlay_plan: Dictionary={}
func regions() -> Array: return Data.resolve(editor._doc.map_meta).get("fortifications",[])
func catalog() -> Dictionary:
	var items: Array=[]
	for r in regions(): items.append({"settings":r.settings,"baked":r.get("baked",false),"source_part_count":r.get("source_part_count",r.parts.size()),"count":r.parts.size(),"modified_or_missing":r.parts.filter(func(p):return Data.token(editor._doc._find(p.id))!=p.signature).map(func(p):return p.id)})
	return {"ok":true,"regions":items}
func owned(region: Dictionary,verify:=true) -> Dictionary:
	var ids:={}
	for part in region.get("parts",[]):
		var r: Dictionary=editor._doc._find(part.id)
		if not r.is_empty() and not editor._record_editable(r): return Data.fail("城墙含锁定、隐藏或隔层构件")
		if verify and (r.is_empty() or Data.token(r)!=part.signature): return Data.fail("城墙构件已手改或删除，请恢复修改或解除关联保留现场")
		ids[part.id]=true
	return {"ok":true,"ids":ids}
func paint(r: Dictionary,material: Dictionary) -> Dictionary:
	var node: MeshInstance3D=editor._doc._mesh(r); var geometry:=Paint.geometry(node); node.free()
	if not geometry.ok: return geometry
	var entries: Array=[]; var tile: Array=material.get("tile_size",[1,1])
	for slot in geometry.surfaces.size():
		var surface: Dictionary=geometry.surfaces[slot]
		for face in surface.faces: entries.append({"mesh":".","surface":slot,"face":face,"geometry":surface.signature,"material":material.duplicate(true),"mapping":"uv" if r.has("channel_mesh") else "meters","scale":[1.0/tile[0],1.0/tile[1]],"offset":[0,0],"rotation":0.0})
	r.surface_paint=entries
	return {"ok":true} if Paint.valid(r) and Paint.missing([r]).is_empty() else Data.fail("城墙材质依赖缺失")
func prepare(args: Dictionary,gate_control:=false) -> Dictionary:
	var schema:=F.request_schema()
	# Operating an already-saved legacy gate must not silently rebuild its dimensions.
	# Public generation requests always keep the >=5m schema.
	if gate_control: schema.properties.gates=F.W.arr(F.gate_schema(),16)
	var issue:=F.S.validate(args,schema)
	if not issue.is_empty(): return Data.fail(issue)
	var old: Dictionary={}
	for r in regions():
		if r.settings.id==args.id: old=r
	if old.get("baked",false):return Data.fail("已烘焙的城防结构不可重生成；城门开合请用城门状态操作")
	if old.is_empty() and regions().size()>=64: return Data.fail("城墙最多 64 组")
	var settings:=F.defaults();
	if old.is_empty(): settings.style="medieval_stone"; settings.height=7.5; settings.thickness=3.5; settings.arrow_slits=true; settings.wall_access=true; settings.tower_count=0; settings.tower_layout="automatic"
	settings.merge(old.get("settings",{}),true); var changes:=args.duplicate(true); changes.erase("plan_token"); settings.merge(changes,true)
	if old.is_empty() and settings.style=="plain":
		if not changes.has("wall_access"): settings.wall_access=false
		if not changes.has("arrow_slits"): settings.arrow_slits=false
	if not gate_control: settings.layout_version=1
	if settings.shape=="ellipse": settings.closed=true
	if not F.valid_settings(settings): return Data.fail("城墙路径或参数无效：写实城门最低净高须 ≥ 5 米，墙顶须高于门洞至少 0.5 米；登墙通路要求写实样式、塔楼、至少 3.2 米墙厚和 7.5 米墙高；射击孔需要写实样式")
	var owner:=owned(old)
	if not owner.ok: return owner
	var result:=Plan.new().build(settings)
	if not result.ok:
		result.settings=settings; return result
	if not gate_control and settings.tower_layout=="automatic":
		var centers:=Spacing.record_centers(result.records)
		for region in regions():
			if region.settings.id==settings.id: continue
			var other:=F.defaults().merged(region.settings,true)
			if other.base_height+other.height<settings.base_height or settings.base_height+settings.height<other.base_height: continue
			var existing: Array=editor._doc.records.filter(func(r):return r.get("fortification",{}).get("id","")==other.id)
			var checked:=Spacing.cross_validate(centers,Spacing.gates(settings),Spacing.radius(settings),Spacing.record_centers(existing),Spacing.gates(other),Spacing.radius(other))
			if not checked.ok:
				checked.settings=settings; checked.layout_zones=Spacing.zones(Spacing.record_centers(existing),Spacing.gates(other),Spacing.radius(settings)); return checked
	var materials:={}
	for role in ["stone","door","trim","floor"]:
		var id: String=settings[role+"_material_id"]
		if id.is_empty() and settings.style=="medieval_stone":
			id={"floor":"pack:default:paving/sandstone_floor/material","stone":"pack:default:walls/castle_rubble/material","trim":"pack:default:walls/stone_tiles_facade/material","door":"pack:default:wood/worn_planks/material"}[role]
			settings[role+"_material_id"]=id
		if not id.is_empty():
			materials[role]=editor._material_tool.library.find(id)
			if materials[role].is_empty(): return Data.fail("城墙材质不存在："+id)
	var kit_path:=preload("res://scripts/world3d/map_paths.gd").external_root().path_join("packs/default/assets/fortifications/medieval_stone/medieval_wall.glb")
	if settings.style=="medieval_stone":
		if preload("res://scripts/world3d/fortification_art.gd").new().kit(kit_path).is_empty(): return Data.fail("写实城墙 Blender 模块库缺失，请安装默认资源包")
		materials.iron={"name":"锻铁","color":[.075,.068,.055,1.0],"roughness":.78,"metallic":.72}
	var token:=Data.token([settings,editor._doc.records,Data.resolve(editor._doc.map_meta),editor._authoring.settings,materials])
	if args.has("plan_token") and args.plan_token!=token: return Data.fail("城墙预览已过期，请重新预览")
	var obstacles: Array=[]; var buildings:={}
	var site:=preload("res://scripts/world_editor/fortification_site.gd").new()
	for r in editor._doc.records:
		if owner.ids.has(r.uuid): continue
		if r.has("building"):
			if not buildings.has(r.building.id): buildings[r.building.id]=[]
			buildings[r.building.id].append(r); continue
		var shapes:=Foot.record_shapes(r)
		var blocked: Array=[]
		for shape in shapes:
			var foundation_support: bool=settings.terrain_foundation and r.has("terrain_mesh") and r.get("collision","")!="none" and shape.top_max_y<=settings.base_height+.035 and shape.top_min_y>=settings.base_height-settings.foundation+.02
			if Foot.level_ground(r,shape,settings.base_height) or foundation_support: site.add(shape,r.uuid,true)
			else: blocked.append(shape)
		for shape in blocked: site.add(shape,r.uuid,false,r.has("road_mesh"))
	for id in buildings: obstacles.append({"id":id,"road":false,"shapes":Foot.components(buildings[id],Vector3.ZERO,Basis.IDENTITY)})
	for shape in preload("res://scripts/world3d/planning_zones.gd").obstacles(editor._doc.map_meta): obstacles.append({"id":"planning_zone","road":false,"shapes":[shape]})
	var data:=Data.resolve(editor._doc.map_meta); var graph: Dictionary=data.roads; var analysis:=Data.analyze(graph)
	if not analysis.ok: return analysis
	for edge in graph.edges:
		var points: Array=analysis.paths[edge.id]
		for i in points.size()-1:
			var a:=Vector2(points[i].x,points[i].z); var b:=Vector2(points[i+1].x,points[i+1].z); var n:=Vector2(-(b-a).y,(b-a).x).normalized()*maxf(edge.width_start,edge.width_end)*.5
			var shape:=preload("res://scripts/world3d/waterway_plan.gd").shape([a-n,b-n,b+n,a+n],minf(points[i].y,points[i+1].y),maxf(points[i].y,points[i+1].y)+data.get("road_surface",{}).get("settings",{}).get("clearance",3.0))
			obstacles.append({"id":edge.id,"road":true,"shapes":[shape]})
	for obstacle in obstacles:
		for shape in obstacle.shapes: site.add(shape,obstacle.id,false,obstacle.road)
	var water_support: Array=[]
	for gate in settings.gates:
		if gate.get("kind","land")!="water": continue
		var i:=int(gate.segment); var a:=Vector2(settings.points[i][0],settings.points[i][1]); var b:=Vector2(settings.points[(i+1)%settings.points.size()][0],settings.points[(i+1)%settings.points.size()][1]); var d:=(b-a).normalized()
		water_support.append({"polygon":preload("res://scripts/world3d/fortification_access.gd").rectangle(a.lerp(b,gate.t),d,-gate.width*.5,gate.width*.5,settings.thickness+.1),"bottom":settings.base_height+gate.height})
	var parts: Array=[]; var checks:=0; var support_cache:={}; var issues: Array=[]
	for r in result.records:
		if not owner.ids.has(r.uuid) and editor._doc.has_uuid(r.uuid): return Data.fail("城墙构件 ID 冲突")
		if not editor._authoring.Settings.contains(r,editor._authoring.settings): return Data.fail("城墙构件落在当前隔离楼层外")
		var shapes:=Foot.record_shapes(r); var valid_site:=true
		for shape in shapes:
			var nearby:=site.query(shape.bounds)
			var key:=str(shape.polygon)+str(shape.bounds.position.y)
			# Hinged leaves are suspended from the validated jamb, not supported
			# by every point of their swing. Their swept collision is still tested.
			if r.has("fixture"): support_cache[key]=true
			elif not support_cache.has(key):
				var local_support: Array=nearby.filter(func(e):return e.support).map(func(e):return e.shape.polygon)
				for opening in water_support:
					if shape.bounds.position.y>=opening.bottom-.01: local_support.append(opening.polygon)
				support_cache[key]=Scatter.inside(shape.polygon,local_support)
			if not support_cache[key]:
				issues.append({"ok":false,"error":"城墙构件缺少地面承托或地基下延不足："+r.fortification.part,"part":r.fortification.part,"position":r.position}); valid_site=false; break
			for obstacle in nearby:
				if obstacle.support or obstacle.road and r.has("fixture"): continue
				checks+=1
				if checks>4000000: return Data.fail("城墙碰撞检查超过预算，请分段生成")
				if Foot.overlaps(shape,obstacle.shape):
					issues.append({"ok":false,"error":"城墙或城门活动范围与现有物件 / 道路净空重叠","conflicts":[obstacle.id],"part":r.fortification.part,"position":r.position}); valid_site=false; break
			if not valid_site: break
		if issues.size()>=32: return issues[0].merged({"issues":issues})
		if not issues.is_empty(): continue

		var role: String="floor" if settings.layout_version==1 and r.fortification.role=="access_floor" else ("door" if r.has("fixture") else "stone")
		if settings.style=="medieval_stone" and r.fortification.role in preload("res://scripts/world3d/fortification_art.gd").MODULES and (not r.has("channel_mesh") or r.fortification.role=="corner_tower" or r.channel_mesh.polygons.all(func(p):return p.size()==4)):
			var module: String=r.fortification.role
			if module=="corner_tower" and settings.shape=="ellipse": module="round_tower"
			r.fortification_art={"version":1,"module":module,"asset_path":kit_path}
			r.fortification_materials=materials.duplicate(true); r.fortification_materials.erase("floor")
			if not F.valid_record(r) or not Paint.valid(r) or not Paint.missing([r]).is_empty(): return Data.fail("写实城墙模块或材质无效")
		elif materials.has(role):
			var painted:=paint(r,materials[role])
			if not painted.ok: return painted
		parts.append({"id":r.uuid,"signature":Data.token(r)})
	if not issues.is_empty(): return issues[0].merged({"issues":issues})
	if editor._doc.records.size()-owner.ids.size()+result.records.size()>100000: return Data.fail("生成后超过地图物件上限")
	result.manifest={"version":1,"settings":settings,"parts":parts}; result.excluded=owner.ids; result.plan_token=token
	data.fortifications=regions().filter(func(r):return r.settings.id!=settings.id); data.fortifications.append(result.manifest)
	if not Data.valid({"editor_layout":data}): return Data.fail("城墙配方未通过保存校验")
	result.metadata=data; return result
func summary(args: Dictionary) -> Dictionary:
	var r:=prepare(args)
	if not r.ok: return r
	return {"ok":true,"settings":r.manifest.settings,"count":r.records.size(),"length":r.length,"gates":r.gates,"outline":r.get("outline",r.manifest.settings.points),"plan_token":r.plan_token,"access_routes":r.get("access_routes",[]),"layout_zones":r.get("layout_zones",[]),"tower_count":Spacing.record_centers(r.records).size(),"layout_rules":{"applied":r.manifest.settings.tower_layout=="automatic","min_tower_spacing":50.0,"gate_clearance":10.0}}
func generate(args: Dictionary,gate_control:=false) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var r:=prepare(args,gate_control)
	if not r.ok: return r
	if Data.token(r.metadata)==Data.token(Data.resolve(editor._doc.map_meta)): return {"ok":true,"changed":false,"count":r.records.size()}
	var frozen:=freeze(r.records,r.manifest)
	if not frozen.ok:return frozen
	r.records=frozen.records
	editor._doc.checkpoint_recovery(); editor._doc.records=editor._doc.records.filter(func(item):return not r.excluded.has(item.uuid)); editor._doc.records.append_array(r.records); editor._doc.map_meta.editor_layout=r.metadata; editor._dirty=true; editor._rebuild()
	return {"ok":true,"changed":true,"count":r.records.size(),"ids":r.records.map(func(item):return item.uuid)}
func set_gate(id: String,gate_id: String,amount: float) -> Dictionary:
	var ready:Dictionary=editor._city.guard()
	if not ready.ok:return ready
	if not is_finite(amount) or amount<0 or amount>1:return Data.fail("开度必须为 0～1")
	for r in regions():
		if r.settings.id!=id: continue
		if r.get("baked",false):
			var owner:=owned(r)
			if not owner.ok:return owner
			var members:Array=editor._doc.records.filter(func(item):return owner.ids.has(item.uuid) and item.get("fixture",{}).get("id","")==gate_id)
			if members.is_empty():return Data.fail("城门不存在或水关没有门扇")
			editor._doc.checkpoint_recovery()
			for item in members:item.fixture.open=amount
			for gate in r.settings.gates:
				if gate.id==gate_id:gate.open=amount
			for part in r.parts:part.signature=Data.token(editor._doc._find(part.id))
			var data:=Data.resolve(editor._doc.map_meta);data.fortifications=data.fortifications.filter(func(item):return item.settings.id!=id);data.fortifications.append(r);editor._doc.map_meta.editor_layout=data
			editor._dirty=true;editor._rebuild();return {"ok":true,"changed":true}
		var gates: Array=r.settings.gates.duplicate(true)
		for gate in gates:
			if gate.id==gate_id: gate.open=amount; return generate({"id":id,"gates":gates},true)
	return Data.fail("城墙或城门不存在")
func remove(id: String,keep: bool) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var old: Dictionary={}
	for r in regions():
		if r.settings.id==id: old=r
	if old.is_empty(): return Data.fail("城墙不存在")
	if keep and old.get("baked",false):return Data.fail("固定城防预制件不能解除关联拆成散件")
	var owner:=owned(old,not keep)
	if not owner.ok: return owner
	editor._doc.checkpoint_recovery()
	if not keep: editor._doc.records=editor._doc.records.filter(func(r):return not owner.ids.has(r.uuid))
	else:
		for r in editor._doc.records:
			if owner.ids.has(r.uuid):
				preload("res://scripts/world3d/building_fixtures.gd").bake_snapshot(r); r.erase("fortification")
	var data:=Data.resolve(editor._doc.map_meta); data.fortifications=regions().filter(func(r):return r.settings.id!=id); editor._doc.map_meta.editor_layout=data; editor._dirty=true; editor._rebuild(); return {"ok":true}

static func freeze(records:Array,manifest:Dictionary)->Dictionary:
	var result:=preload("res://scripts/world3d/structure_prefab.gd").fortification(records)
	if not result.ok:return result
	manifest.baked=true;manifest.source_part_count=records.size();manifest.parts=[]
	for r in result.records:manifest.parts.append({"id":r.uuid,"signature":Data.token(r)})
	return result

func bake(id:String)->Dictionary:
	var ready:Dictionary=editor._city.guard()
	if not ready.ok:return ready
	for region in regions():
		if region.settings.id!=id:continue
		if region.get("baked",false):return Data.fail("城防已经烘焙")
		var owner:=owned(region)
		if not owner.ok:return owner
		var manifest:Dictionary=region.duplicate(true)
		var result:=freeze(editor._doc.records.filter(func(r):return owner.ids.has(r.uuid)),manifest)
		if not result.ok:return result
		editor._doc.checkpoint_recovery()
		editor._doc.records=editor._doc.records.filter(func(r):return not owner.ids.has(r.uuid));editor._doc.records.append_array(result.records)
		var data:=Data.resolve(editor._doc.map_meta)
		data.fortifications=data.fortifications.filter(func(r):return r.settings.id!=id);data.fortifications.append(manifest)
		editor._doc.map_meta.editor_layout=data;editor._dirty=true;editor._rebuild()
		return {"ok":true,"source_count":result.source_count,"component_count":result.component_count}
	return Data.fail("城防不存在")
