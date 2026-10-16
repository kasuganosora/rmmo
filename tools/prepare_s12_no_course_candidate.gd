extends "res://tools/build_house_playground.gd"
## Offline authoring only. Reuses accepted house parameters with current materials.
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/s12_no_course_candidate"
const SOURCE="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Footprint=preload("res://scripts/world_editor/building_footprint.gd")
class Registry extends RefCounted:
	var values:Dictionary={}
	func instances()->Dictionary:return values
class PaintHost extends Node3D:
	var _view:Node3D
	var _buildings:Registry=Registry.new()
func publish_index(value:Dictionary)->void:
	var target:=OUT+"/house_templates.json";var temporary:=target+".authoring.tmp"
	var file:=FileAccess.open(temporary,FileAccess.WRITE);file.store_string(JSON.stringify(value,"\t"));file.close()
	check(DirAccess.rename_absolute(temporary,target)==OK,"atomic template index publication")
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT+"/templates")
	var inventory:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SOURCE+"/source_house_inventory.json"))
	var low:Dictionary=inventory.families.filter(func(r):return r.id=="building_083c47c0d96f3497f32d")[0].duplicate(true)
	low.id="s2_low_gable";low.parameters.roof_axis="depth";inventory.families.append(low)
	var stone:Dictionary=inventory.families.filter(func(r):return r.id=="building_34340ded1777777e6628")[0].duplicate(true)
	stone.id="s1_narrow_stone";stone.exterior_material="pack:default:walls/lime_plaster/material";inventory.families.append(stone)
	var selected:="s12_arch_hall"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):selected=arg.trim_prefix("--only=")
	if FileAccess.file_exists(SOURCE+"/extra_house_parameters.json"):
		var extra:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SOURCE+"/extra_house_parameters.json"))
		inventory.families.append_array(extra.get("families",[]))
	for row:Dictionary in preload("res://scripts/world_editor/surface_material_library.gd").new().entries():definitions[row.material_id]=row.material
	for id:String in IDS.values():check(definitions.has(id),"current material "+id)
	if failed:quit(1);return
	editor=PaintHost.new();root.add_child(editor)
	var results:Array=[]
	if not selected.is_empty() and FileAccess.file_exists(OUT+"/house_templates.json"):
		results=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/house_templates.json")).templates.filter(func(r):return r.id!=selected)
	for item:Dictionary in inventory.families:
		var id:String=item.id
		if not selected.is_empty() and id!=selected:continue
		var parameters:Dictionary=item.parameters.duplicate(true)
		parameters.template="house";parameters.front_canopy=false
		parameters.front_string_course="none"
		var plan:Dictionary=Blueprint.generate(parameters)
		check(plan.ok,"house blueprint "+id)
		if not plan.ok:quit(1);return
		# Register the generator's canonical complete parameters. Special recipes
		# are sparse inputs; persisting them directly fails native metadata save.
		parameters=plan.parameters.duplicate(true)
		var local:Array=plan.records
		for i in local.size():local[i].uuid="template_%d"%i;local[i].building.id=id
		var paintdoc=Doc.new();paintdoc.records=local
		editor._view=paintdoc.build();editor.add_child(editor._view)
		editor._buildings.values={id:{"parameters":parameters,"yaw":0}}
		var validation:Dictionary={}
		for r:Dictionary in local:
			# These production fixtures already own UV-authored materials. Per-face
			# generic projection would overwrite their artwork and exceed face limits.
			if r.get("building",{}).get("role")=="light_sconce" or r.get("building_shape","") in ["timber_door","interior_door","interior_door_frame"]:continue
			var faces:Dictionary=author_faces(r)
			if not faces.ok:check(false,"author faces "+r.uuid);quit(1);return
			var entries:Array=[]
			for face:Dictionary in faces.faces:
				var role:=material_role(r,face);var entry:Dictionary=face.target.duplicate(true)
				entry.merge({"mapping":"meters","scale":[1,1],"rotation":0,"offset":[0,0]})
				entry.merge(settings_for(r,face,role),true)
				var material_id:String=item.get("exterior_material",IDS[role]) if role=="plaster" else IDS[role]
				entry.material=definitions[material_id].duplicate(true);entries.append(entry)
			r.surface_paint=entries
			if not Paint.valid(r,false,"",validation):
				FileAccess.open(OUT+"/paint_failure.json",FileAccess.WRITE).store_string(JSON.stringify(r,"\t"));check(false,"surface paint "+r.uuid);quit(1);return
		editor._view.free()
		var frozen:Dictionary=Prefab.bake(local)
		check(frozen.ok,"native freeze "+id)
		if not frozen.ok:quit(1);return
		var value:Dictionary={"version":Blueprint.VERSION,"parameters":parameters,"position":[0,0,0],"yaw":0,"parts":{},"signatures":{},"baked":true,"source_part_count":frozen.source_count}
		for i in frozen.records.size():
			var r:Dictionary=frozen.records[i];r.uuid="house_template_%d"%i;r.building.id=id;r.editor_group=id;r.editor_group_name="住宅模板"
			value.parts[r.building.part]=r.uuid;value.signatures[r.building.part]=Blueprint.geometry_signature(r)
		var loaded:Dictionary={"records":frozen.records,"building_instances":{id:value}}
		check(Blueprint.valid_ownership({"building_instances":loaded.building_instances},loaded.records),"ownership "+id)
		check(Blueprint.valid_meta({"building_instances":loaded.building_instances}),"saveable complete building metadata "+id)
		if failed:quit(1);return
		var bounds:AABB=Footprint.local_bounds(frozen.records)
		var row:Dictionary={"id":id,"source_id":id,"parameters":parameters,"loaded_path":OUT+"/templates/"+id+".json","entrance":plan.entrance,"door_threshold":[float(plan.entrance[0]),float(parameters.base_height),-float(parameters.depth)/2],"bounds":{"position":Blueprint.arr(bounds.position),"size":Blueprint.arr(bounds.size)},"foundation_min_y":bounds.position.y,"source_parts":local.size(),"frozen_parts":frozen.records.size(),"review":{"resource":"pending","visual":"pending","pipeline":"ownership_passed","formal_integration":"pending"}}
		FileAccess.open(row.loaded_path,FileAccess.WRITE).store_string(JSON.stringify(loaded))
		row.sha256=FileAccess.get_sha256(row.loaded_path);results.append(row)
		if selected.is_empty():publish_index({"complete":false,"templates":results,"failures":failed})
		print("HOUSE_TEMPLATE_READY ",id," ",frozen.records.size());await process_frame
	publish_index({"complete":true,"templates":results,"failures":failed,"materials":definitions})
	editor.free();quit(failed)
