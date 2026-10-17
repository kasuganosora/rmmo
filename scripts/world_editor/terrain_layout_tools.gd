extends RefCounted
## A bounded final-state transaction: terrain stamps and existing road nodes.
## Staging is private; no intermediate surface ever enters the live document.
const T=preload("res://scripts/world3d/terrain_surface.gd")
const Batch=preload("res://scripts/world3d/terrain_stroke_batch.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Layer=preload("res://scripts/world3d/terrain_river_layer.gd")
const Outlet=preload("res://scripts/world3d/terrain_river_outlet.gd")
const Follow=preload("res://scripts/world_editor/terrain_follow_tools.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const MAX_WORK_VERTICES:=2000000
const MAX_CHANGED_CELLS:=262144

class Stage extends Node3D:
	var source:Node3D
	var _doc=Doc.new()
	var _roads=preload("res://scripts/world_editor/road_tools.gd").new()
	var _terrain=preload("res://scripts/world_editor/terrain_tools.gd").new()
	var _fortifications=preload("res://scripts/world_editor/fortification_tools.gd").new()
	var _waterways=preload("res://scripts/world_editor/waterway_tools.gd").new()
	var _material_tool:Variant
	var _authoring:Variant
	func setup(editor:Node3D)->void:
		source=editor;_doc.apply_recovery(editor._doc.recovery_snapshot())
		_material_tool=editor._material_tool;_authoring=editor._authoring
		_roads.editor=self;_terrain.editor=self;_fortifications.editor=self;_waterways.editor=self
	func _record_editable(record:Dictionary)->bool:return source._record_editable(record)

static func schema()->Dictionary:
	var stroke:=T.stroke_schema().duplicate(true)
	stroke.properties.mode={"type":"string","enum":["flatten"]}
	stroke.properties.shape={"type":"string","enum":["rectangle"]}
	stroke.properties.points.maxItems=1
	stroke.required=["id","mode","shape","points","plot_width","plot_depth","target_height"]
	return City.object({"strokes":City.array(stroke,16,1),"road_nodes":City.array(City.object({"id":City.text(),"position":T.S.vector(-100000,100000)},["id","position"]),64),"expected_road_token":City.text(64)},["strokes"])

static func node_changes(data:Dictionary,args:Dictionary)->Dictionary:
	var requested:Array=args.get("road_nodes",[])
	if not requested.is_empty() and args.get("expected_road_token","")!=City.token(data.roads):return City.fail("道路草案已变化，请重新读取 road_token 再联合整坡")
	var nodes:Dictionary={};var changed:Dictionary={};var seen:Dictionary={}
	for node:Dictionary in data.roads.nodes:nodes[node.id]=node
	for move:Dictionary in requested:
		if seen.has(move.id) or not nodes.has(move.id):return City.fail("联合整坡只能更新不重复的现有道路节点")
		seen[move.id]=true
		var node:Dictionary=nodes[move.id]
		if node.get("hidden",false) or node.get("locked",false):return City.fail("请先解锁并显示道路节点")
		if Layer.same(node.position,move.position):continue
		for edge:Dictionary in data.roads.edges:
			if move.id in [edge.from,edge.to] and (edge.get("hidden",false) or edge.get("locked",false)):return City.fail("节点连接着锁定或隐藏的道路，请先解除保护")
		node.position=move.position.duplicate();changed[move.id]=true
	var checked:=City.analyze(data.roads)
	if not checked.ok:return checked
	var bridges:=preload("res://scripts/world3d/road_bridges.gd").resolve(data)
	if not bridges.ok:return bridges
	return {"ok":true,"ids":changed.keys()}

static func owned_roads(stage:Node3D,data:Dictionary)->Dictionary:
	var ids:Dictionary={}
	for part:Dictionary in data.get("road_surface",{}).get("parts",[]):
		var record:Dictionary=stage._doc._find(part.id)
		if record.is_empty() or record.get("road_source","")!=part.key or Surface.signature(record)!=part.signature:return City.fail("道路铺面已被手改或删除，不能联合整坡")
		if not stage._record_editable(record):return City.fail("道路铺面包含锁定、隐藏或隔层构件")
		ids[part.id]=true
	return {"ok":true,"ids":ids}

static func river_history(source:Node3D,layers:Array,updated:Dictionary)->Dictionary:
	# Validate the current authoring history, without modifying it. A receiving
	# river's `after` is legitimately covered by a later declared tributary.
	# Only that explicit dependency may be virtually undone before checking it.
	if not Outlet.valid_links({"terrain_rivers":layers}):return City.fail("河道汇流依赖无效，不能联合整坡")
	var selected:Dictionary={};var indexed:Dictionary={};var by_id:Dictionary={}
	for record:Dictionary in source._doc.records:indexed[record.uuid]=record
	for layer:Dictionary in layers:
		by_id[layer.id]=layer
		for item:Dictionary in layer.terrains:
			if updated.has(item.after.uuid):selected[layer.id]=true
	var owners:Dictionary={};var appearance:Dictionary={}
	for layer:Dictionary in layers:
		var id:String=layer.id
		for item:Dictionary in layer.terrains:
			var tile:String=item.after.uuid
			if not owners.has(tile):owners[tile]={};appearance[tile]={}
			for i in item.after.terrain_mesh.heights.size():
				if Layer.same(item.before.terrain_mesh.heights[i],item.after.terrain_mesh.heights[i]):continue
				if not owners[tile].has(i):owners[tile][i]=[]
				owners[tile][i].append(id)
			for field:String in Layer.APPEARANCE_FIELDS:
				if Layer.same(item.before.get(field),item.after.get(field)):continue
				if not appearance[tile].has(field):appearance[tile][field]=[]
				appearance[tile][field].append(id)
	for target:String in selected:
		# Start from real current state for EACH owner. Never globally unwind
		# independent rivers, which could hide an undeclared overlapping write.
		var current:=indexed.duplicate();var pending:Dictionary={target:true}
		var grew:=true
		while grew:
			grew=false
			for layer:Dictionary in layers:
				if not pending.has(layer.id) and pending.has(layer.request.get("outlet",{}).get("river_id","")):
					pending[layer.id]=true;grew=true
		var restored_ids:Dictionary={}
		while not pending.is_empty():
			var leaf:String=""
			for id:String in pending:
				var has_child:=false
				for child:String in pending:
					if by_id[child].request.get("outlet",{}).get("river_id","")==id:has_child=true;break
				if not has_child:leaf=id;break
			if leaf.is_empty():return City.fail("河道汇流依赖形成循环")
			var layer:Dictionary=by_id[leaf]
			for part:Dictionary in layer.water:
				if City.token(current.get(part.id,{}))!=part.signature:return City.fail("河道水面已手改或删除，请先恢复河道关联")
			# Restore all of the descendant's tiles, including mouth tiles outside
			# the proposed stamp; Outlet.prepare validates the full receiving mouth.
			for item:Dictionary in layer.terrains:
				var restored:=Layer.restore(current.get(item.after.uuid,{}),item.before,item.after)
				if not restored.ok:return restored
				current[item.after.uuid]=restored.record
			var context:=Outlet.prepare(source,layer.request,layers,current.values())
			if not context.ok:return context
			for item:Dictionary in layer.terrains:
				for field:String in appearance[item.after.uuid]:
					var shared_fields:Array=appearance[item.after.uuid][field]
					if leaf in shared_fields and shared_fields.size()>1:return City.fail("河道材质归属重叠，不能作为汇流河床叠层恢复")
				for at:int in owners[item.after.uuid]:
					var sharing:Array=owners[item.after.uuid][at]
					if leaf not in sharing:continue
					for other:String in sharing:
						if other==leaf or restored_ids.has(other):continue
						if not Outlet.allows(context,other,item.after,at):return City.fail("河道采样叠层没有有效的直接汇流关系，不能联合整坡")
			pending.erase(leaf);restored_ids[leaf]=true
	return {"ok":true}

static func river_guard(source:Node3D,changes:Array)->Dictionary:
	var updated:Dictionary={}
	for entry:Dictionary in changes:updated[entry.record.uuid]=entry.record
	var layers:Array=source._doc.map_meta.get("terrain_rivers",[])
	var history:=river_history(source,layers,updated)
	if not history.ok:return history
	for layer:Dictionary in layers:
		var relevant:=false
		for item:Dictionary in layer.terrains:
			if not updated.has(item.after.uuid):continue
			relevant=true
			var before:Dictionary=source._doc._find(item.after.uuid)
			for i in item.after.terrain_mesh.heights.size():
				if Layer.same(item.before.terrain_mesh.heights[i],item.after.terrain_mesh.heights[i]):continue
				if not Layer.same(before.terrain_mesh.heights[i],updated[item.after.uuid].terrain_mesh.heights[i]):return City.fail("联合整坡会改变河道 "+layer.id+" 控制的河床采样，请修改该河道配方")
		if relevant:
			for part:Dictionary in layer.water:
				if City.token(source._doc._find(part.id))!=part.signature:return City.fail("河道水面已手改或删除，请先恢复河道关联")
	# A river can depend on a sample that already had the requested height;
	# such a sample has no before/after delta. Reuse its full-footprint guard.
	var dependency:=preload("res://scripts/world_editor/terrain_river_tools.gd").restoration_conflict(source,"",source._doc.map_meta.get("terrain_rivers",[]),updated)
	if not dependency.is_empty():return City.fail(dependency)
	return {"ok":true}

static func replace_records(doc:RefCounted,entries:Array,removed:Array=[])->void:
	var updated:Dictionary={}
	for entry:Dictionary in entries:updated[entry.record.uuid]=entry.record
	var records:Array=[]
	for record:Dictionary in doc.records:
		if record.uuid in removed:continue
		records.append(updated.get(record.uuid,record));updated.erase(record.uuid)
	records.append_array(updated.values());doc.records=records

static func work_budget(stage:Node3D,strokes:Array)->Dictionary:
	var work:=0;var by_seed:Dictionary={}
	for stroke:Dictionary in strokes:
		var seed:Dictionary=stage._doc._find(stroke.id)
		if not seed.has("terrain_mesh") or not stage._record_editable(seed):return City.fail("目标必须是可见、解锁且在当前楼层的地形").merged({"code":"protected_scope","terrain_id":stroke.id})
		var key:=str([stroke.id,stroke.get("cross_tiles",true)])
		if not by_seed.has(key):
			var vertices:=0
			var sources:Array=Batch.connected(stage._doc.records,seed) if stroke.get("cross_tiles",true) else [seed]
			for tile:Dictionary in sources:vertices+=tile.terrain_mesh.heights.size()
			by_seed[key]=vertices
		work+=int(by_seed[key])
		if work>MAX_WORK_VERTICES:return City.fail("联合整坡超过整组 200 万地形顶点处理预算，请缩小地形组或减少矩形数量")
	return {"ok":true}

static func prepare(editor:Node3D,args:Dictionary)->Dictionary:
	var ready:Dictionary=editor._city.guard()
	if not ready.ok:return ready
	var error:=T.S.validate(args,schema())
	if not error.is_empty():return City.fail(error)
	if not City.valid(editor._doc.map_meta):return City.fail("现有道路或河道关联无效，不能联合整坡")
	var stage:=Stage.new();stage.setup(editor)
	var result:=prepare_stage(editor,stage,args)
	stage.free()
	return result

static func prepare_stage(editor:Node3D,stage:Node3D,args:Dictionary)->Dictionary:
	var data:=City.resolve(stage._doc.map_meta)
	var graph:=node_changes(data,args)
	if not graph.ok:return graph
	if stage._doc.map_meta.has("editor_layout") or not graph.ids.is_empty():stage._doc.map_meta.editor_layout=data
	var owned:=owned_roads(stage,data)
	if not owned.ok:return owned
	# Stamps never alter grid shape/transforms. Count the entire request before
	# doing expensive sampling, including repeated/no-op stamps on the same tile.
	var budget:=work_budget(stage,args.strokes)
	if not budget.ok:return budget
	var touched:Dictionary={};var samples:=0
	for stroke:Dictionary in args.strokes:
		var seed:Dictionary=stage._doc._find(stroke.id)
		if not seed.has("terrain_mesh") or not stage._record_editable(seed):return City.fail("目标必须是可见、解锁且在当前楼层的地形").merged({"code":"protected_scope","terrain_id":stroke.id})
		if seed.has("surface_paint"):return City.fail("地形上有手刷表面，不能联合整坡")
		var batch:=Batch.prepare(stage._doc.records,seed,stroke)
		if not batch.ok:return batch
		samples+=batch.samples
		for entry:Dictionary in batch.entries:
			var previous:Dictionary=stage._doc._find(entry.record.uuid)
			if not stage._record_editable(previous) or previous.has("surface_paint"):return City.fail("跨块整坡触及锁定、隐藏、隔层或手刷地形，整组取消").merged({"code":"protected_scope","terrain_id":previous.uuid})
			touched[entry.record.uuid]=true
		replace_records(stage._doc,batch.entries)
	var changes:Array=[];var cell_count:=0
	for id:String in touched:
		var before:Dictionary=editor._doc._find(id);var next:Dictionary=stage._doc._find(id);var cells:Array=[]
		for z in int(next.terrain_mesh.rows):
			for x in int(next.terrain_mesh.columns):
				var at:int=z*int(next.terrain_mesh.columns)+x
				if before.terrain_mesh.holes[at]!=next.terrain_mesh.holes[at] or T.cell(before,x,z)!=T.cell(next,x,z):cells.append(at)
		if not cells.is_empty():changes.append({"record":next,"cells":cells,"changed":true});cell_count+=cells.size()
		if cell_count>MAX_CHANGED_CELLS:return City.fail("联合整坡最终修改超过 262144 格预算，请缩小范围")
	if changes.is_empty() and graph.ids.is_empty():
		return {"ok":true,"changed":false,"changed_cells":0,"samples":samples,"terrain_ids":[],"updated_road_nodes":[],"road_token":City.token(data.roads),"road_diff":{"added":0,"updated":0,"unchanged":owned.ids.size(),"removed":0},"changed_ids":[]}
	var river:=river_guard(editor,changes)
	if not river.ok:return river
	var terrain_ids:Array=changes.map(func(entry):return entry.record.uuid)
	var participants:Array=terrain_ids+owned.ids.keys()+Follow.affected(editor._doc.records,terrain_ids).map(func(r):return r.uuid)+Follow.fort_ids(editor,changes)
	var contact_cache:Dictionary={}
	for entry:Dictionary in changes:
		var checked:Dictionary=editor._terrain.validate_change(editor._doc._find(entry.record.uuid),entry,participants,contact_cache)
		if not checked.ok:return checked
	# Old generated road records are replaced in this private candidate. Their
	# ownership was proven above and RoadTools.prepare below checks every paint,
	# event, lock, bridge portal and final collision before any live mutation.
	# Non-road followers must see the final ground, not the old road contour.
	var roads:Array=stage._doc.records.filter(func(r):return owned.ids.has(r.uuid))
	stage._doc.records=stage._doc.records.filter(func(r):return not owned.ids.has(r.uuid))
	var followed:=Follow.prepare(stage,changes)
	if not followed.ok:return followed
	replace_records(stage._doc,followed.entries,followed.removed)
	stage._doc.map_meta=followed.map_meta
	stage._doc.records.append_array(roads)
	var road_diff:={"added":0,"updated":0,"unchanged":roads.size(),"removed":0}
	if data.has("road_surface"):
		var prepared:Dictionary=stage._roads.prepare({},City.resolve(stage._doc.map_meta))
		if not prepared.ok:return prepared
		stage._doc.records=stage._doc.records.filter(func(r):return not prepared.excluded.has(r.uuid))
		stage._doc.records.append_array(prepared.records)
		var final_layout:=City.resolve(stage._doc.map_meta)
		final_layout.roads=prepared.graph;final_layout.road_surface=prepared.manifest
		stage._doc.map_meta.editor_layout=final_layout;road_diff=prepared.diff
	var changed_ids:Array=[];var final_ids:Dictionary={}
	for record:Dictionary in stage._doc.records:
		final_ids[record.uuid]=true
		if Layer.same(record,editor._doc._find(record.uuid)):continue
		if stage._doc.validate_save_record(record)!=OK:return City.fail("联合整坡结果包含不可保存的构件："+record.uuid)
		changed_ids.append(record.uuid)
	for record:Dictionary in editor._doc.records:
		if not final_ids.has(record.uuid):changed_ids.append(record.uuid)
	if not City.valid(stage._doc.map_meta):return City.fail("联合整坡结果的道路或河道关联无效")
	var changed:bool=not changed_ids.is_empty() or not Layer.same(stage._doc.map_meta,editor._doc.map_meta)
	return {"ok":true,"changed":changed,"changed_cells":cell_count,"samples":samples,"terrain_ids":terrain_ids,"updated_road_nodes":graph.ids,"road_token":City.token(City.resolve(stage._doc.map_meta).roads),"road_diff":road_diff,"changed_ids":changed_ids,"records":stage._doc.records,"map_meta":stage._doc.map_meta}

static func public_result(result:Dictionary)->Dictionary:
	var summary:=result.duplicate()
	summary.erase("records");summary.erase("map_meta")
	return summary

static func preview(editor:Node3D,args:Dictionary)->Dictionary:
	return public_result(prepare(editor,args))

static func apply(editor:Node3D,args:Dictionary)->Dictionary:
	var result:=prepare(editor,args)
	return commit_prepared(editor,result)

## Only synchronous, fully validated private candidates may enter this boundary.
static func commit_prepared(editor:Node3D,result:Dictionary)->Dictionary:
	if not result.ok or not result.changed:return public_result(result)
	editor._doc.checkpoint_recovery()
	editor._doc.records=result.records;editor._doc.map_meta=result.map_meta
	editor._dirty=true
	var refresh:Array[String]=[]
	for id:String in result.changed_ids:refresh.append(id)
	editor._refresh_records(refresh)
	editor._selection_tools.invalidate_pivot();editor._refresh_selection(false)
	editor._object_list.refresh();editor._city.refresh()
	if editor._terrain_panel!=null:editor._terrain_panel.refresh()
	return public_result(result)
