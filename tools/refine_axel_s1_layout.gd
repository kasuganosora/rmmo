extends "res://tools/apply_axel_reference_layout.gd"
## Scene-only refinement using native 3D HTTP operations and current guards.
var baseline:Dictionary={}
var allowed:Dictionary={}
func operation(tool:String,args:Dictionary)->Dictionary:
	var result:=await super.operation(tool,args)
	if not result.get("ok",false):
		if not report.has("diagnostics"):report.diagnostics=[]
		report.diagnostics.append({"tool":tool,"result":result});persist()
	return result
func before_placements(recipe:Dictionary)->void:
	report.scene_id="s1_bridge"
	report.scope="S1 bridgehead approach, courtyard trees, roadside canopy and spire sightline"
	check(FileAccess.get_sha256(recipe.root_source.path)==recipe.root_source.sha256,"unchanged formal S12 root")
	if failed:return
	baseline=Doc.open_file(recipe.root_source.path).recovery_snapshot()
	report.root_source_sha256=recipe.root_source.sha256
	for field:String in ["changed_records","deleted_records","new_records"]:
		for id:String in report.get(field,[]):allowed[id]=true
	report.samples=[]
	for point:Array in recipe.get("terrain_samples",[]):
		var sample:=await operation("sample_terrain_height",{"id":"axel_terrain_05_04","point":point})
		report.samples.append(sample)
		if failed:return
	for row:Dictionary in recipe.get("pre_moves",[]):
		var record:Dictionary=editor._doc._find(row.id)
		var old_at:=City.vec(record.position);var at:=City.vec(row.position)
		if row.get("preserve_ground_offset",false):at.y=Props.ground(editor._doc,at)+old_at.y-Props.ground(editor._doc,old_at)
		await operation("set_object_transform",{"id":row.id,"position":City.xyz(at)})
		allowed[row.id]=true
		if failed:return
		var now:Dictionary=editor._doc._find(row.id)
		report.placements=report.placements.filter(func(p):return p.id!=row.id)
		report.placements.append({"id":row.id,"key":row.key,"position":now.position,"scale":now.size})
	for row:Dictionary in recipe.get("flag_spans",[]):
		var a:Dictionary=editor._doc._find(row.left);var b:Dictionary=editor._doc._find(row.right)
		var pa:=City.vec(a.position);var pb:=City.vec(b.position)
		pa.y+=float(a.bounds_size[1])*float(a.size[1])-.2
		pb.y+=float(b.bounds_size[1])*float(b.size[1])-.2
		var delta:=pb-pa;var length_xz:=Vector2(delta.x,delta.z).length()
		var euler:=Vector3(0,atan2(-delta.z,delta.x),atan2(delta.y,length_xz))
		var at:Vector3=(pa+pb)*.5-Basis.from_euler(euler)*Vector3(0,2.35,0)
		await operation("set_object_transform",{"id":row.id,"position":City.xyz(at),"rotation":City.xyz(euler*180./PI),"size":[delta.length()/11.3,1,1]})
		allowed[row.id]=true
		var now:Dictionary=editor._doc._find(row.id)
		report.placements=report.placements.filter(func(p):return p.id!=row.id)
		report.placements.append({"id":row.id,"key":"s1/bridgehead_flag_span","position":now.position,"scale":now.size})
		if failed:return
	if recipe.has("road_request"):
		var layout:=await operation("get_city_layout",{})
		var request:Dictionary=recipe.road_request.duplicate(true);request.expected_token=layout.road_token
		for node:Dictionary in request.get("nodes",[]):node.position[1]=Props.ground(editor._doc,City.vec(node.position))
		await operation("update_road_graph",request)
func after_placements(recipe:Dictionary)->void:
	for row:Dictionary in report.placements:allowed[row.id]=true
	await super.after_placements(recipe)
	if failed:return
	var doc=editor._doc
	report.tree_clearance=[]
	for id:String in recipe.get("trees",[]):
		var tree:Dictionary=doc._find(id);var conflicts:Array=[]
		for record:Dictionary in doc.records:
			if not record.has("building") and not record.has("model_building"):continue
			if Foot.batches_overlap(Foot.record_shapes(tree),Foot.record_shapes(record)):conflicts.append(record.uuid)
		check(conflicts.is_empty(),"whole crown avoids houses "+id)
		report.tree_clearance.append({"id":id,"conflicts":conflicts})
	report.changed_records=[];report.deleted_records=[];report.new_records=[]
	var prior:Dictionary={}
	for old:Dictionary in baseline.records:
		prior[old.uuid]=true;var now:Dictionary=doc._find(old.uuid)
		if City.token(old)==City.token(now):continue
		check(allowed.has(old.uuid) or old.has("road_mesh"),"only S1 placement or native road changed "+str(old.uuid))
		if now.is_empty():report.deleted_records.append(old.uuid)
		else:report.changed_records.append(old.uuid)
	for row:Dictionary in doc.records:
		if prior.has(row.uuid):continue
		check(allowed.has(row.uuid) or row.has("road_mesh"),"only scoped S1 object added "+str(row.uuid));report.new_records.append(row.uuid)
	var a:Dictionary=baseline.map_meta.duplicate(true);var b:Dictionary=doc.map_meta.duplicate(true)
	a.building_instances.erase("building_061ac981f7e8922e09fa")
	for meta:Dictionary in [a,b]:
		meta.editor_layout.erase("roads");meta.editor_layout.erase("road_surface")
		meta.town_reference.house_layout.placements=meta.town_reference.house_layout.placements.filter(func(r):return r.get("id","")!="s1_north_courtyard")
	check(City.token(a)==City.token(b),"S12, remaining houses, water, terrain and spawn preserved")
