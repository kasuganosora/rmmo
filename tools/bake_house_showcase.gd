extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const SOURCE="D:/code/rmmo_runtime/maps/medieval_house_showcase_v8/map.gltf"
const EXPECTED="b392d7a0cea89a052560398a2b5269cfcace1b2a277f990bc26e80b0047b7cee"
func _initialize()->void:call_deferred("run")
func run()->void:
	if FileAccess.get_sha256(SOURCE).to_lower()!=EXPECTED:push_error("Showcase changed; refusing conversion");quit(1);return
	var doc=Doc.open_file(SOURCE)
	if doc==null:quit(1);return
	var compiler=preload("res://scripts/world_editor/building_tools.gd").new()
	var registry:Dictionary=doc.map_meta.building_instances.duplicate(true)
	var records:Array=doc.records.filter(func(r):return not r.has("building"))
	for id:String in registry:
		var value:Dictionary=registry[id]
		var source:Array=doc.records.filter(func(r):return r.get("building",{}).get("id","")==id)
		for r:Dictionary in source:
			if r.get("editor_locked",false) or r.get("editor_hidden",false) or B.geometry_signature(r)!=value.signatures.get(r.building.part):
				push_error("Building is protected or modified: "+str(r.uuid));quit(1);return
		var plan:={"position":value.position,"yaw":value.yaw,"records":source}
		var result:Dictionary=compiler.freeze_plan(plan)
		if not result.ok:push_error(str(result));quit(1);return
		value.parts={};value.signatures={};value.baked=true;value.source_part_count=source.size()
		for r:Dictionary in plan.records:
			r.uuid="obj_%d"%doc._next;doc._next+=1;r.building.id=id;r.editor_group=id;r.editor_group_name=B.LABELS[value.parameters.template]
			value.parts[r.building.part]=r.uuid;value.signatures[r.building.part]=B.geometry_signature(r);records.append(r)
		print("BAKED_SHOWCASE ",id," ",source.size()," -> ",plan.records.size())
	doc.records=records;doc.map_meta.building_instances=registry
	var path:String=preload("res://scripts/world3d/map_paths.gd").cache_directory("house_prefab_showcase_validation").path_join("map.gltf")
	if "--publish" in OS.get_cmdline_user_args():path=SOURCE
	var error:int=doc.save(path)
	if error!=OK or Doc.open_file(path)==null:push_error("Baked save/reopen failed: "+str(error));quit(1);return
	print("BAKED_SHOWCASE_SAVED ",path," records=",records.size()," sha256=",FileAccess.get_sha256(path));quit()
