extends "res://tools/apply_axel_reference_layout.gd"
## Reuse a reviewed frozen residential instance through native whole-building tools.
const OLD_BACK="building_19d4aeac100dd1547fea"
const SOURCE_BACK="building_074cc23f7a1865cd083b"
var baseline:Dictionary={}
var permitted:Dictionary={}
var new_back_id:=""
func before_placements(recipe:Dictionary)->void:
	baseline=editor._doc.recovery_snapshot()
	report.scene_id="S10"
	report.scope="S10 background-house reuse and local soft grass region; front house/tree remain pending art delivery"
	report.root_source_sha256=recipe.root_source.sha256
	check(FileAccess.get_sha256(recipe.root_source.path)==recipe.root_source.sha256,"exact unchanged formal revision")
	var buildings:Dictionary=editor._doc.map_meta.building_instances
	check(buildings.has(OLD_BACK) and buildings.has(SOURCE_BACK),"existing background and reviewed round-window source")
	if failed:return
	var old:Dictionary=buildings[OLD_BACK].duplicate(true)
	for id:String in old.parts.values():permitted[id]=true
	await operation("delete_building",{"id":OLD_BACK})
	if failed:return
	var previous:Array=buildings.keys()
	await operation("select_objects",{"ids":[buildings[SOURCE_BACK].parts.values()[0]]})
	var source_value:Dictionary=buildings[SOURCE_BACK].duplicate(true)
	var saved:=await operation("save_prefab",{"name":"S10 可复用双层拱窗住宅","pack_root":"D:/code/rmmo_runtime/packs/default"})
	if failed:return
	var loaded:Dictionary=preload("res://scripts/world_editor/prefab_library.gd").read(saved.entry)
	check(loaded.get("ok",false) and loaded.building_instances.size()==1,"complete unchanged frozen house library capture")
	if failed:return
	var local:Dictionary=loaded.building_instances.values()[0]
	var target:=City.vec(old.position)-City.vec(local.position)
	# The existing exterior lamp is attached to the facade being replaced.
	# Hold this independently editable fitting aside, then remount it at its
	# original doorway; retain all unrelated obstacles during native placement.
	var lamp:Dictionary=editor._doc._find("obj_844").duplicate(true)
	await operation("set_object_transform",{"id":"obj_844","position":[97.45,9.87934,143.5]})
	var probe=Doc.new();probe.apply_recovery(editor._doc.recovery_snapshot())
	var placement_probe:=preload("res://scripts/world_editor/prefab_library.gd").place(probe,saved.entry,target)
	report.native_placement_probe=placement_probe;persist()
	print("S10_NATIVE_PLACEMENT ",JSON.stringify(placement_probe))
	await operation("place_asset",{"asset_id":saved.asset_id,"position":City.xyz(target)})
	if failed:return
	await operation("set_object_transform",{"id":"obj_844","position":lamp.position})
	buildings=editor._doc.map_meta.building_instances
	var added:Array=buildings.keys().filter(func(id):return not previous.has(id))
	check(added.size()==1,"one independent native background house")
	if failed:return
	new_back_id=added[0]
	var copied:Dictionary=buildings[new_back_id]
	# Native library placement checks actual terrain cells, foundation support,
	# every neighbour and the existing entry road. No road or terrain exemption.
	report.reused_prefab={"asset_id":saved.asset_id,"sha256":FileAccess.get_sha256(saved.asset_id)}
	check(City.token(source_value)==City.token(buildings[SOURCE_BACK]),"source S2 frozen house unchanged")
	check(City.vec(copied.position).distance_to(City.vec(old.position))<.001,"same background footprint and floor elevation")
	for id:String in copied.parts.values():
		permitted[id]=true
		report.placements.append({"id":id,"key":"s10/background_house_component"})
	report.background_replacement={"old":OLD_BACK,"new":new_back_id,"reused_from":SOURCE_BACK,"position":copied.position,"parts":copied.parts.values()}
	for row:Dictionary in editor._doc.map_meta.town_reference.house_layout.placements:
		if row.get("id","")!="s10_back_home":continue
		row.building_id=new_back_id;row.previous_building_id=OLD_BACK;row.parameters=copied.parameters.duplicate(true)
		row.template_id="building_10e2848ee287d056ac56";row.component_ids=copied.parts.values()
		row.label="果树前院背景两层拱窗住宅"
	await operation("paint_terrain_region",recipe.ground_region)
	for id:String in recipe.ground_region.terrain_ids:permitted[id]=true
func after_placements(recipe:Dictionary)->void:
	await super.after_placements(recipe)
	if failed:return
	report.changed_records=[];report.deleted_records=[];report.new_records=[]
	var old_ids:Dictionary={}
	for old:Dictionary in baseline.records:
		old_ids[old.uuid]=true
		var now:Dictionary=editor._doc._find(old.uuid)
		if City.token(old)==City.token(now):continue
		check(permitted.has(old.uuid) or old.has("road_mesh"),"only declared S10 objects and native path derivation changed "+str(old.uuid))
		if now.is_empty():report.deleted_records.append(old.uuid)
		else:
			report.changed_records.append(old.uuid)
			if old.has("terrain_mesh"):
				var a:=old.duplicate(true);var b:=now.duplicate(true)
				a.erase("terrain_regions");b.erase("terrain_regions")
				check(City.token(a)==City.token(b),"terrain geometry and original base material preserved "+str(old.uuid))
	for now:Dictionary in editor._doc.records:
		if old_ids.has(now.uuid):continue
		check(permitted.has(now.uuid) or now.has("road_mesh"),"new record belongs to reused S10 background house or native path "+str(now.uuid));report.new_records.append(now.uuid)
	var old_meta:Dictionary=baseline.map_meta.duplicate(true);var new_meta:Dictionary=editor._doc.map_meta.duplicate(true)
	old_meta.building_instances.erase(OLD_BACK);new_meta.building_instances.erase(new_back_id)
	for meta:Dictionary in [old_meta,new_meta]:
		meta.editor_layout.erase("roads");meta.editor_layout.erase("road_surface")
		meta.town_reference.house_layout.placements=meta.town_reference.house_layout.placements.filter(func(row):return row.get("id","")!="s10_back_home")
	check(City.token(old_meta)==City.token(new_meta),"all other shots, native roads, terrain heights, spawn and metadata preserved")
