extends RefCounted
const V=preload("res://scripts/world3d/terrain_volume.gd")
const T=preload("res://scripts/world3d/terrain_surface.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
static func apply(editor:Node3D,args:Dictionary,stroke:=false,preview:=false)->Dictionary:
	var guard:Dictionary=editor._gameplay.guard()
	if not guard.ok:return guard
	var error:=V.S.validate(args,V.stroke_schema() if stroke else V.request_schema())
	if not error.is_empty():return T.fail(error)
	var previous:Dictionary=editor._doc._find(args.id);var next:Dictionary={}
	if not str(args.id).is_valid_identifier():return T.fail("体积地形 ID 无效")
	if not previous.is_empty() and (not previous.has("terrain_volume") or not editor._record_editable(previous)):return T.fail("目标不是可编辑体积地形")
	if stroke:
		if previous.is_empty():return T.fail("体积地形不存在")
		if previous.has("surface_paint"):return T.fail("请先清除手刷面材质，再修改体积拓扑")
		next=previous.duplicate(true);var inverse:=T.transform(next).affine_inverse()
		for i in maxi(1,args.points.size()-1):
			var a:Vector3=inverse*V.vector(args.points[i]);var b:Vector3=inverse*V.vector(args.points[mini(i+1,args.points.size()-1)])
			next.terrain_volume.operations.append({"mode":args.mode,"a":[a.x,a.y,a.z],"b":[b.x,b.y,b.z],"radius":args.radius})
	else:
		if not previous.is_empty():return T.fail("体积地形已存在，请雕刻或删除后重建")
		next={"uuid":args.id,"kind":"box","position":args.center.duplicate(),"size":args.size.duplicate(),"rotation":[0,0,0],"color":[.44,.43,.38],"surface_id":"ground","collision":"walk","editor_name":args.get("name","体积地形"),"terrain_volume":{"version":1,"resolution":args.get("resolution",16),"seed":args.get("seed","box"),"operations":[]}}
		var material:Dictionary=editor._terrain.material(args.get("material_id",""))
		if not material.ok:return material
		if not material.material.is_empty():next.terrain_material=material.material
	if not V.valid(next):return T.fail("体积地形参数超出范围或计算预算，请拆分为较小地块")
	if not editor._authoring.Settings.contains(next,editor._authoring.settings):return T.fail("体积地形超出隔离楼层")
	# Keep props and authored terrain safe; carving below a support is also a change.
	var footprint:=Foot.record_shape(next)
	for record:Dictionary in editor._doc.records:
		if record.uuid==next.uuid:continue
		if Foot.batches_overlap([footprint],Foot.record_shapes(record)):return T.fail("体积范围内存在物件或其他地形，请先移开以免破坏承托："+str(record.uuid))
	for shape:Dictionary in preload("res://scripts/world3d/planning_zones.gd").obstacles(editor._doc.map_meta):
		if Foot.batches_overlap([footprint],[shape]):return T.fail("体积地形触及保留区")
	var arrays:=V.arrays(next)
	if arrays.is_empty():return T.fail("笔画将移除全部体积，请使用删除物件")
	if preview:return {"ok":true,"id":next.uuid,"triangles":arrays[0][Mesh.ARRAY_INDEX].size()/3,"operations":next.terrain_volume.operations.size()}
	editor._doc.checkpoint()
	if previous.is_empty():editor._doc.records.append(next)
	else:editor._doc.records[editor._doc.records.find(previous)]=next
	# Reuse the verified CPU result for this publication; subsequent loads use the
	# same background surface preparation and record-sensitive derived cache.
	var saved:Dictionary=editor._doc.load_surface_arrays
	editor._doc.load_surface_arrays={str(next.uuid):arrays};editor._commit_records([next.uuid]);editor._doc.load_surface_arrays=saved
	return {"ok":true,"id":next.uuid,"operations":next.terrain_volume.operations.size()}
