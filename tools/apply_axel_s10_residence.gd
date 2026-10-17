extends "res://tools/apply_axel_reference_layout.gd"
## S10 composition assembled through current HTTP editor operations.
const FRONT="building_2f6d20abcdba46dee584"
const BACK="building_19d4aeac100dd1547fea"
const Imported=preload("res://scripts/world3d/imported_building.gd")
var formal_snapshot:Dictionary={}
var permitted:Dictionary={}
var back_id:=""
var unchanged_residence:Dictionary={}
var unchanged_roads:Dictionary={}

func before_placements(recipe:Dictionary)->void:
	report.scene_id="S10"
	report.scope="S10 fruit-tree court, shutter residence, reused arched background residence and connected entry paths"
	report.root_source_sha256=recipe.root_source.sha256
	check(FileAccess.get_sha256(recipe.root_source.path)==recipe.root_source.sha256,"formal revision unchanged before S10 assembly")
	if failed:return
	var formal=Doc.open_file(recipe.root_source.path)
	check(formal!=null,"formal comparison source opens")
	if failed:return
	formal_snapshot=formal.recovery_snapshot()
	var parent:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(recipe.parent_authoring.path))
	check(parent.get("scene_id","")=="S10" and parent.get("saved",false) and parent.get("failures",-1)==0,"successful S10 native layout preparation")
	if failed:return
	report.background_replacement=parent.background_replacement.duplicate(true)
	back_id=parent.background_replacement.new
	if recipe.get("refine_existing",false):
		for row:Dictionary in report.placements:
			if row.key=="s10/front_residence":unchanged_residence=editor._doc._find(row.id).duplicate(true)
		check(not unchanged_residence.is_empty() and parent.has("house_components"),"unchanged residence has exact prior native component evidence")
		if failed:return
		report.house_components=parent.house_components.duplicate(true)
	if not recipe.get("validate_roads",false):
		check(not recipe.has("road_request") and parent.get("road_validation",{}).get("ok",false),"exact parent has successful road validation for unchanged graph")
		if failed:return
		unchanged_roads=editor._doc.map_meta.editor_layout.duplicate(true)
		report.road_validation=parent.road_validation.duplicate(true)
		report.road_validation_reused_from=recipe.parent_authoring
	for building:String in [FRONT,BACK]:
		check(formal_snapshot.map_meta.building_instances.has(building),"declared original S10 residence "+building)
		if failed:return
		for id:String in formal_snapshot.map_meta.building_instances[building].parts.values():permitted[id]=true
	for id:String in parent.background_replacement.parts:permitted[id]=true
	for id:String in ["obj_840","obj_842","obj_843","obj_844","obj_882","axel_terrain_01_01","axel_terrain_01_02","axel_terrain_02_02"]:permitted[id]=true
	for receipt:Dictionary in recipe.art_receipts:
		check(FileAccess.get_sha256(receipt.path)==receipt.sha256,"exact reviewed art delivery "+receipt.path.get_file())
	if failed:return
	if not recipe.get("refine_existing",false):
		await operation("delete_building",{"id":FRONT})
	if recipe.has("ground_region"):
		await operation("paint_terrain_region",recipe.ground_region)
		var painted:Dictionary=editor._doc._find("axel_terrain_02_02")
		check(painted.get("terrain_regions",{}).get("regions",[]).any(func(region):return region.id==recipe.ground_region.id),"courtyard grass actually present on intersecting terrain tile")
		if failed:return
	for id:String in recipe.get("remove_ids",[]):
		check(id in ["obj_842","obj_843","obj_882"],"only superseded S10 prop removed "+id)
		if failed:return
		await operation("select_objects",{"ids":[id]})
		await operation("delete_selection",{})
		report.placements=report.placements.filter(func(row):return row.id!=id)
		if failed:return
	if recipe.has("road_request"):
		var layout:=await operation("get_city_layout",{})
		var roads:Dictionary=recipe.road_request.duplicate(true)
		roads.expected_token=layout.road_token
		for node:Dictionary in roads.get("nodes",[]):node.position[1]=Props.ground(editor._doc,City.vec(node.position))
		await operation("update_road_graph",roads)

func after_placements(recipe:Dictionary)->void:
	var doc=editor._doc
	var house:Dictionary={};var tree:Dictionary={}
	for row:Dictionary in report.placements:
		permitted[row.id]=true
		if row.key=="s10/front_residence":house=doc._find(row.id)
		if row.key=="s10/mature_fruit_tree":tree=doc._find(row.id)
	check(not house.is_empty() and Imported.verify_source(house),"S10 front residence retains imported building contract")
	check(not tree.is_empty(),"independent reviewed S10 tree present")
	if failed:return
	if recipe.get("refine_existing",false):
		check(City.token(house)==City.token(unchanged_residence),"residence record unchanged; reuse exact earlier native component inspection")
	else:
		report.house_components=await operation("list_building_components",{"id":house.uuid})
	if failed:return
	# Full canopy bounds, not just the trunk, must clear both residence shells.
	var tree_bounds:AABB=Foot.record_shape(tree).bounds
	var house_bounds:AABB=Foot.record_shape(house).bounds
	check(not tree_bounds.grow(.12).intersects(house_bounds),"complete tree canopy clears front residence")
	var back_records:Array=[]
	for id:String in doc.map_meta.building_instances[back_id].parts.values():back_records.append(doc._find(id))
	var back_bounds:AABB=preload("res://scripts/world_editor/selection_geometry.gd").bounds(back_records)
	check(not tree_bounds.grow(.12).intersects(back_bounds),"complete tree canopy clears background residence")
	await super.after_placements(recipe)
	if failed:return
	if not recipe.get("validate_roads",false):
		check(City.token(unchanged_roads)==City.token(doc.map_meta.editor_layout),"road graph and native surface settings unchanged since exact parent validation")
		if failed:return
	for row:Dictionary in doc.map_meta.town_reference.house_layout.placements:
		if row.get("id","")!="s10_front_home":continue
		row.previous_building_id=FRONT
		for key:String in ["building_id","parameters","component_ids","template_id","terrain_range"]:row.erase(key)
		row.object_id=house.uuid;row.position=house.position;row.rotation=house.rotation;row.yaw=house.rotation[1]
		row.entrance=recipe.front_entrance
		row.label="红果树前院窗板住宅"
		row.component_ids=report.placements.filter(func(p):return str(p.key).begins_with("s10/")).map(func(p):return p.id)
		row.reference_stage="S10 reference arrangement; outdoor image and access review required"
	report.changed_records=[];report.deleted_records=[];report.new_records=[]
	var old_ids:Dictionary={}
	for old:Dictionary in formal_snapshot.records:
		old_ids[old.uuid]=true
		var now:Dictionary=doc._find(old.uuid)
		if City.token(old)==City.token(now):continue
		check(permitted.has(old.uuid) or old.has("road_mesh"),"only declared S10 objects or native paths changed "+str(old.uuid))
		if now.is_empty():report.deleted_records.append(old.uuid)
		else:
			report.changed_records.append(old.uuid)
			if old.has("terrain_mesh"):
				var a:=old.duplicate(true);var b:=now.duplicate(true);a.erase("terrain_regions");b.erase("terrain_regions")
				check(City.token(a)==City.token(b),"original terrain geometry and base material retained "+str(old.uuid))
	for now:Dictionary in doc.records:
		if old_ids.has(now.uuid):continue
		check(permitted.has(now.uuid) or now.has("road_mesh"),"new S10-owned instance or native path "+str(now.uuid))
		report.new_records.append(now.uuid)
	var old_meta:Dictionary=formal_snapshot.map_meta.duplicate(true);var new_meta:Dictionary=doc.map_meta.duplicate(true)
	old_meta.building_instances.erase(FRONT);old_meta.building_instances.erase(BACK);new_meta.building_instances.erase(back_id)
	for meta:Dictionary in [old_meta,new_meta]:
		meta.editor_layout.erase("roads");meta.editor_layout.erase("road_surface")
		meta.town_reference.house_layout.placements=meta.town_reference.house_layout.placements.filter(func(r):return r.get("id","") not in ["s10_front_home","s10_back_home"])
	check(City.token(old_meta)==City.token(new_meta),"S1 manual area, S2, S12, all other houses, water and spawn metadata unchanged")
