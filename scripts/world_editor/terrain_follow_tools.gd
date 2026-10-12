extends RefCounted
const ProjectTerrain=preload("res://scripts/world3d/terrain_projection.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
static func affected(records:Array,ids:Array)->Array:
	return records.filter(func(r):return r.has("terrain_follow") and r.terrain_follow.terrain_ids.any(func(id):return id in ids))
static func prepare(editor:Node3D,changes:Array,defer_fortifications:bool=false)->Dictionary:
	var updated:Dictionary={}
	for entry:Dictionary in changes:updated[entry.record.uuid]=entry.record
	var followers:=affected(editor._doc.records,updated.keys());var ids:Array=updated.keys()+followers.map(func(r):return r.uuid)
	ids.append_array(fort_ids(editor,changes))
	var terrains:Array=[]
	for r:Dictionary in editor._doc.records:
		if r.has("terrain_mesh"):terrains.append(updated.get(r.uuid,r))
	var result:Array=[];var metadata:Dictionary=editor._doc.map_meta.duplicate(true)
	for previous:Dictionary in followers:
		if not editor._record_editable(previous):return City.fail("跟随地形的铺面被锁定、隐藏或隔层，整笔取消")
		if previous.has("event") or previous.has("event_template"):return City.fail("跟随铺面有事件，请先解除贴地关联")
		var binding:Dictionary=previous.terrain_follow
		var fitted:=ProjectTerrain.fit(previous,terrains,binding.offset,binding.max_grade)
		if not fitted.ok:return fitted
		var next:Dictionary=fitted.record;var paint:Array=previous.get("surface_paint",[])
		if not paint.is_empty():
			var material:Dictionary=paint[0].material
			if not paint.all(func(p):return p.material==material and p.mapping=="uv" and p.rotation==0. and p.offset==[0,0]):return City.fail("贴地铺面含手工刷面，不能自动覆盖")
			next.erase("surface_paint")
			var painted:Dictionary=editor._roads.paint_default(next,material) if next.has("road_mesh") else editor._waterways.paint(next,material)
			if not painted.ok:return painted
		var shapes:=Foot.record_shapes(next)
		if Foot.batches_overlap(shapes,preload("res://scripts/world3d/planning_zones.gd").obstacles(editor._doc.map_meta)):return City.fail("贴地更新侵入保留区或保留通道")
		for obstacle:Dictionary in editor._doc.records:
			if obstacle.uuid in ids or obstacle.uuid in next.terrain_follow.terrain_ids:continue
			if Foot.batches_overlap(shapes,Foot.record_shapes(obstacle)):return City.fail("贴地更新侵入物件或通行净空："+str(obstacle.uuid))
		if not editor._authoring.Settings.contains(next,editor._authoring.settings):return City.fail("贴地更新超出当前楼层")
		result.append({"record":next})
		for part:Dictionary in metadata.get("editor_layout",{}).get("road_surface",{}).get("parts",[]):
			if part.id==next.uuid:
				part.signature=preload("res://scripts/world3d/road_surface.gd").signature(next)
				part.paint_signature=City.token(next.get("surface_paint",[]))

	var fort_ids_:Array=fort_ids(editor,changes);var removed:Array=[]
	if defer_fortifications:
		for region:Dictionary in editor._fortifications.regions():
			if not region.parts.any(func(part):return part.id in fort_ids_):continue
			var checked:Dictionary=editor._fortifications.owned(region)
			if not checked.ok:return checked
		return {"ok":true,"entries":result,"map_meta":metadata,"removed":removed}
	for entry:Dictionary in result:updated[entry.record.uuid]=entry.record
	var proposed:Array=editor._doc.records.map(func(r):return updated.get(r.uuid,r))
	for region:Dictionary in metadata.get("editor_layout",{}).get("fortifications",[]):
		if not region.parts.any(func(part):return part.id in fort_ids_):continue
		var args:Dictionary=region.settings.duplicate(true);args.erase("layout_version")
		# Internal regeneration preserves all legacy controls; public authored
		# requests retain their bounded schema.
		var plan:Dictionary=editor._fortifications.prepare(args,true,proposed)
		if not plan.ok:return plan
		var frozen:Dictionary=editor._fortifications.freeze(plan.records,plan.manifest)
		if not frozen.ok:return frozen
		for part:Dictionary in region.parts:removed.append(part.id)
		for record:Dictionary in frozen.records:result.append({"record":record})
		proposed=proposed.filter(func(r):return r.uuid not in region.parts.map(func(part):return part.id))
		proposed.append_array(frozen.records)
		region.parts=plan.manifest.parts;region.baked=true;region.source_part_count=plan.manifest.source_part_count
	return {"ok":true,"entries":result,"map_meta":metadata,"removed":removed}

static func fort_ids(editor:Node3D,changes:Array)->Array:
	var ids:Array=[]
	for region:Dictionary in editor._doc.map_meta.get("editor_layout",{}).get("fortifications",[]):
		if not region.settings.get("follow_terrain",false):continue
		var touches:=false
		for part:Dictionary in region.parts:
			var record:Dictionary=editor._doc._find(part.id)
			if record.is_empty():continue
			var bounds:AABB=Foot.record_shape(record).bounds
			for change:Dictionary in changes:
				var terrain_bounds:AABB=Foot.record_shape(change.record).bounds
				if Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z).intersects(Rect2(terrain_bounds.position.x,terrain_bounds.position.z,terrain_bounds.size.x,terrain_bounds.size.z)):touches=true;break
			if touches:break
		if touches:ids.append_array(region.parts.map(func(part):return part.id))
	return ids


