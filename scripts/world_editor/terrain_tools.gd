extends RefCounted
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var editor: Node3D

func catalog() -> Dictionary:
	var rows: Array=[]
	for r in editor._doc.records:
		if not r.has("terrain_mesh"): continue
		var t: Dictionary=r.terrain_mesh
		rows.append({"id":r.uuid,"name":Geometry.label(r),"columns":t.columns,"rows":t.rows,"cell_size":[r.size[0]/t.columns,r.size[2]/t.rows],"holes":t.holes.count(true),"position":r.position,"height_range":[t.heights.min()*r.size[1]+r.position[1],t.heights.max()*r.size[1]+r.position[1]],"editable":editor._record_editable(r),"material":r.get("terrain_material",{}).get("name","")})
	for row in rows:
		row.depth_blend=editor._doc._find(row.id).get("terrain_depth_blend",{}).duplicate(true)
		row.saturation=editor._doc._find(row.id).get("terrain_saturation",1.)
		row.ground_regions=editor._doc._find(row.id).get("terrain_regions",{}).duplicate(true)
		row.slope_blend=editor._doc._find(row.id).get("terrain_slope_blend",{}).duplicate(true)
	return {"ok":true,"terrains":rows}
func material(id: String) -> Dictionary:
	if id.is_empty(): return {"ok":true,"material":{}}
	var value: Dictionary=editor._material_tool.library.find(id)
	if value.is_empty() or not Paint.material_valid(value) or not Paint.missing([{"terrain_material":value}]).is_empty(): return Terrain.fail("地形材质不存在或贴图依赖缺失")
	return {"ok":true,"material":value.duplicate(true)}
func create(args: Dictionary) -> Dictionary:
	var ready: Dictionary=editor._gameplay.guard()
	if not ready.ok: return ready
	var error:=Terrain.S.validate(args,Terrain.create_schema())
	if not error.is_empty(): return Terrain.fail(error)
	var source: Dictionary={}; var next: Dictionary={}
	if args.has("source_id"):
		for key in ["center","width","depth"]:
			if args.has(key): return Terrain.fail("转换地面时沿用现有范围，不可同时传 center/width/depth")
		source=editor._doc._find(args.source_id)
		if not editor._record_editable(source): return Terrain.fail("请先显示、解锁并选择当前楼层的地面")
		if source.get("kind")!="box" or source.get("surface_id") not in ["ground","grass","dirt","sand","stone"] or source.get("invisible",false): return Terrain.fail("仅可转换普通地面方块")
		for key in ["terrain_mesh","channel_mesh","road_mesh","road_source","building","building_shape","tile3d","fortification","fixture","event","event_template","surface_paint"]:
			if source.has(key): return Terrain.fail("不能转换已有生成关联、事件或手刷材质的地面；请另建地形或先处理关联")
		if absf(source.rotation[0])>.0001 or absf(source.rotation[2])>.0001: return Terrain.fail("转换地面需要水平表面")
		next=source.duplicate(true); next.position[1]+=float(source.size[1])*.5; next.size[1]=1.0
	else:
		if editor._doc.records.size()>=100000: return Terrain.fail("地图物件已达上限")
		next={"uuid":"terrain_"+Crypto.new().generate_random_bytes(12).hex_encode(),"kind":"box","surface_id":"ground","position":args.get("center",[0,0,0]).duplicate(),"rotation":[0,0,0],"size":[args.get("width",32.0),1.0,args.get("depth",32.0)],"color":[.38,.43,.29],"collision":"walk"}
	var step: float=args.get("cell_size",1.0); var columns:=ceili(next.size[0]/step); var rows:=ceili(next.size[2]/step)
	if columns<2 or rows<2 or columns>Terrain.MAX_CELLS or rows>Terrain.MAX_CELLS: return Terrain.fail("每块地形每轴需 2～64 格；请调整格距或拆为多块地形")
	var heights: Array=[]; heights.resize((columns+1)*(rows+1)); heights.fill(0.0)
	var holes: Array=[]; holes.resize(columns*rows); holes.fill(false)
	next.terrain_mesh={"version":1,"columns":columns,"rows":rows,"floor":-float(args.get("bedrock_depth",16.0)),"heights":heights,"holes":holes}
	next.collision="walk"; next.editor_name=args.get("name",Geometry.label(source) if not source.is_empty() else "可雕刻地形")
	var chosen:=material(str(args.get("material_id","")))
	if not chosen.ok: return chosen
	if not chosen.material.is_empty(): next.terrain_material=chosen.material
	if not Terrain.valid(next) or not editor._authoring.Settings.contains(next,editor._authoring.settings): return Terrain.fail("地形参数无效或超出隔离楼层")
	# Conversion preserves the same top surface. Fresh terrain must not bury existing objects.
	if source.is_empty():
		var occupied:=Foot.record_shape(next)
		for r in editor._doc.records:
			if Foot.batches_overlap([occupied],Foot.record_shapes(r)): return Terrain.fail("新地形与现有物件重叠，请改为转换该地面或选择空白区域")
	else:
		var old_bottom: float=source.position[1]-source.size[1]*.5
		var extension:=Terrain.bounds(next); extension.size.y=old_bottom-next.position[1]-extension.position.y
		if extension.size.y>0:
			var corners: Array[Vector3]=[]
			for i in 8: corners.append(Terrain.transform(next)*extension.get_endpoint(i))
			var added:=Foot.from_points(corners)
			for r in editor._doc.records:
				if r.uuid==source.uuid: continue
				var b:=Geometry.bounds([r])
				# Foundations already crossing the original ground remain embedded intentionally.
				if b.end.y>=old_bottom-.01: continue
				if Foot.batches_overlap([added],Foot.record_shapes(r)): return Terrain.fail("加深底床会覆盖地下物件，请减小底床深度")
	editor._doc.checkpoint()
	if source.is_empty(): editor._doc.records.append(next)
	else: editor._doc.records[editor._doc.records.find(source)]=next
	editor._dirty=true; editor._rebuild()
	return {"ok":true,"id":next.uuid,"columns":columns,"rows":rows,"converted":not source.is_empty()}
func prepare(args: Dictionary) -> Dictionary:
	var error:=Terrain.S.validate(args,Terrain.stroke_schema())
	if not error.is_empty(): return Terrain.fail(error)
	var record: Dictionary=editor._doc._find(args.id)
	if not record.has("terrain_mesh") or not editor._record_editable(record): return Terrain.fail("目标必须是可见、解锁且在当前楼层的地形")
	if record.has("surface_paint"): return Terrain.fail("地形上有手刷表面；请先清除表面绘制再雕刻，以免覆盖手工材质。整体地形材质不受影响")
	var result:=Terrain.stroke(record,args)
	if not result.ok or not result.changed: return result
	var next: Dictionary=result.record; var t: Dictionary=record.terrain_mesh; var world:=Terrain.transform(record)
	var furrows:=preload("res://scripts/world3d/terrain_furrows.gd").generate(next)
	if not furrows.ok: return furrows
	var changed_volumes: Array=[]
	for at in result.cells:
		var x: int=int(at)%int(t.columns); var z: int=int(at)/int(t.columns)
		if t.holes[at] and next.terrain_mesh.holes[at]: continue
		var p:=Terrain.cell(record,x,z); var q:=Terrain.cell(next,x,z); var low:=INF; var high:=-INF
		for i in 4: low=minf(low,minf(p[i].y,q[i].y)); high=maxf(high,maxf(p[i].y,q[i].y))
		high+=preload("res://scripts/world3d/terrain_furrows.gd").maximum_height(next)
		if t.holes[at]!=next.terrain_mesh.holes[at]: low=t.floor*record.size[1]
		var points: Array[Vector3]=[]
		for v in p: points.append(world*Vector3(v.x,low-.015,v.z)); points.append(world*Vector3(v.x,high+.15,v.z))
		changed_volumes.append(Foot.from_points(points))
	for obstacle in editor._doc.records:
		if obstacle.uuid==record.uuid: continue
		# River water is a non-solid overlay; sculpting the bed through its level is
		# expected. Keep all other props/linings (including hidden ones) protected.
		if obstacle.get("surface_id")=="water" and obstacle.has("channel_mesh") and obstacle.get("collision")=="none": continue
		var bounds:=Foot.record_shape(obstacle)
		if not Foot.batches_overlap(changed_volumes,[bounds]): continue
		if Foot.batches_overlap(changed_volumes,Foot.record_shapes(obstacle)): return {"ok":false,"error":"笔刷会侵入现有物件或移除其地面承托，整笔已拒绝","conflicts":[obstacle.uuid]}
	return result
func summary(args: Dictionary) -> Dictionary:
	var result:=prepare(args)
	if not result.ok: return result
	return {"ok":true,"changed":result.changed,"changed_cells":result.cells.size(),"samples":result.samples,"height_range":[result.record.terrain_mesh.heights.min()*result.record.size[1]+result.record.position[1],result.record.terrain_mesh.heights.max()*result.record.size[1]+result.record.position[1]],"holes":result.record.terrain_mesh.holes.count(true)}
func sculpt(args: Dictionary, interactive: bool=false) -> Dictionary:
	if not interactive:
		var ready: Dictionary=editor._gameplay.guard()
		if not ready.ok: return ready
	var result:=prepare(args)
	if not result.ok: return result
	if not result.changed: return {"ok":true,"changed":false,"changed_cells":0,"samples":result.samples}
	if not interactive: editor._doc.checkpoint()
	var previous: Dictionary=editor._doc._find(args.id); editor._doc.records[editor._doc.records.find(previous)]=result.record
	var refresh_ids: Array[String]=[str(args.id)]
	editor._dirty=true; editor._refresh_records(refresh_ids)
	if not interactive:
		editor._refresh_selection()
		if editor._terrain_panel!=null: editor._terrain_panel.refresh(str(args.id))
	return {"ok":true,"changed":true,"changed_cells":result.cells.size(),"samples":result.samples}
func set_material(id: String, material_id: Variant=null, saturation: float=-1.) -> Dictionary:
	var ready: Dictionary=editor._gameplay.guard()
	if not ready.ok: return ready
	var record: Dictionary=editor._doc._find(id)
	if not record.has("terrain_mesh") or not editor._record_editable(record): return Terrain.fail("请先显示并解锁当前楼层的地形")
	if material_id==null and saturation==-1.: return Terrain.fail("请指定材质或饱和度")
	var chosen: Dictionary=material(str(material_id)) if material_id!=null else {"ok":true,"material":record.get("terrain_material",{}).duplicate(true)}
	if not chosen.ok: return chosen
	if saturation==-1.: saturation=float(record.get("terrain_saturation",1.))
	if not is_finite(saturation) or saturation<0 or saturation>1: return Terrain.fail("底材饱和度需在 0～1")
	if saturation<1. and record.has("surface_paint"): return Terrain.fail("请先清除手刷三角面覆盖，或使用地表区域工具，再调整底材饱和度")
	if (saturation<1. or record.has("terrain_depth_blend") or record.has("terrain_slope_blend") or record.has("terrain_regions")) and not chosen.material.is_empty() and chosen.material.color[3]!=1: return Terrain.fail("渐变地形的整体底材必须不透明")
	if record.get("terrain_material",{})==chosen.material and is_equal_approx(saturation,float(record.get("terrain_saturation",1.))): return {"ok":true,"changed":false}
	editor._doc.checkpoint()
	if chosen.material.is_empty(): record.erase("terrain_material")
	else: record.terrain_material=chosen.material
	if saturation==1.: record.erase("terrain_saturation")
	else: record.terrain_saturation=saturation
	var refresh_ids: Array[String]=[id]
	editor._dirty=true; editor._refresh_records(refresh_ids)
	return {"ok":true,"changed":true}
