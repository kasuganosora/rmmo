extends "res://tools/build_house_playground.gd"
## Scene-only conversion: preserve upper storeys, roofs, slabs and existing doors.
var OUT="D:/code/rmmo_runtime/review_artifacts/bridge_residential_street_20261007"
const FORMAL="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const PREVIOUS="D:/code/rmmo_runtime/review_artifacts/bridge_frontage_setback_20261007"
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
class Registry extends RefCounted:
	var values:Dictionary={}
	func instances()->Dictionary:return values
class PaintHost extends Node3D:
	var _view:Node3D
	var _buildings:Registry=Registry.new()
func affected(r:Dictionary,base:float)->bool:
	var b:Dictionary=r.get("building",{})
	if b.get("floor",-1)!=0:return false
	if r.has("fixture"):return str(r.fixture.id).begins_with("f0/north/front_window/") or str(r.fixture.id).begins_with("f0/north/shutter_front_window")
	return is_equal_approx(float(b.floor_y),base) and b.role not in ["floor","light_sconce"] and not str(b.role).begins_with("roof") and not str(b.part).ends_with("/ceiling")
func match_key(r:Dictionary)->String:
	return str(r.fixture.id) if r.has("fixture") else "ground_shell"
func run()->void:
	Engine.max_fps=30;DirAccess.make_dir_recursive_absolute(OUT)
	if "--publish" in OS.get_cmdline_user_args():
		var p:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/plan.json"))
		var review:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/review.json"))
		check(p.failures==0 and review.failures==0 and review.plan_sha256==FileAccess.get_sha256(OUT+"/plan.json"),"reviewed residential street")
		check(FileAccess.get_sha256(FORMAL)==p.formal_sha256,"formal map unchanged since plan")
		if failed:quit(1);return
		var d=Doc.open_file(FORMAL);d.records=p.records;d.map_meta=p.metadata;d._next=int(p.next)
		check(d.save(FORMAL)==OK,"native atomic residential save")
		print("NATIVE_SAVE_METRICS ",JSON.stringify(d.last_save_metrics))
		var reopened=Doc.open_file(FORMAL)
		check(reopened!=null and equivalent(reopened.records,d.records) and equivalent(reopened.map_meta,d.map_meta),"residential map reopens exactly")
		FileAccess.open(OUT+"/published.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failed,"sha256":FileAccess.get_sha256(FORMAL),"converted":p.converted,"residences":p.houses.size(),"lamps":p.get("lamps",[]).size(),"new_home":p.get("new_home",""),"save_metrics":d.last_save_metrics},"\t"))
		quit(failed);return
	var baseline:=FileAccess.get_sha256(FORMAL)
	var p:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(PREVIOUS+"/plan.json"))
	var extra:Dictionary=Doc.authoritative_extras(FORMAL).extras
	var d=Doc.new();d.records=extra.rmmo_records;d.map_meta=extra.duplicate(true);d.map_meta.erase("rmmo_records");d._next=320000
	var original:Array=d.records.duplicate(true);var original_meta:Dictionary=d.map_meta.duplicate(true)
	d.checkpoint_recovery()
	for row:Dictionary in preload("res://scripts/world_editor/surface_material_library.gd").new().entries():definitions[row.material_id]=row.material
	for id:String in IDS.values():check(definitions.has(id),"PBR available "+id)
	editor=PaintHost.new();root.add_child(editor)
	var changed:Array=[];var converted:Array=[];var merged:Array=[]
	for house:Dictionary in p.houses:
		var id:String=house.id;var old:Dictionary=d.map_meta.building_instances[id]
		if old.parameters.template!="shop":continue
		var parameters:Dictionary=old.parameters.duplicate(true);parameters.template="house";parameters.front_canopy=false
		var own:Array=d.records.filter(func(r):return r.get("building",{}).get("id")==id)
		check(own.all(func(r):return not r.get("editor_locked",false)),"residence editable "+id)
		var generated:Dictionary=Blueprint.generate(parameters)
		check(generated.ok,"residential blueprint "+id)
		if not generated.ok:quit(1);return
		var local:Array=generated.records.filter(func(r):return affected(r,parameters.base_height))
		var previous_blueprint:Dictionary=Blueprint.generate(old.parameters)
		var previous_source_count:int=previous_blueprint.records.filter(func(r):return affected(r,old.parameters.base_height)).size()
		if parameters.window_style=="tall_shutter":check(local.any(func(r):return str(r.get("fixture",{}).get("id","")).begins_with("f0/north/shutter_front_window")),"front shutters match whole-house window family "+id)
		check(not local.any(func(r):return str(r.building.part).contains("shop") or str(r.building.part).begins_with("porch/")),"no sales counter or shop canopy "+id)
		var paintdoc=Doc.new()
		for index in local.size():local[index].building.id=id;local[index].uuid="paint_%d"%index
		paintdoc.records=local;editor._view=paintdoc.build();editor.add_child(editor._view)
		editor._buildings.values={id:{"parameters":parameters,"yaw":0}}
		var validation:Dictionary={}
		for r:Dictionary in local:
			var faces:Dictionary=author_faces(r);check(faces.ok,"author faces "+r.uuid) if not faces.ok else null
			if not faces.ok:quit(1);return
			var entries:Array=[]
			for face:Dictionary in faces.faces:
				var role:=material_role(r,face);var entry:Dictionary=face.target.duplicate(true)
				entry.merge({"mapping":"meters","scale":[1,1],"rotation":0,"offset":[0,0]})
				entry.merge(settings_for(r,face,role),true);entry.material=definitions[IDS[role]].duplicate(true);entries.append(entry)
			r.surface_paint=entries
			if not Paint.valid(r,false,"",validation):check(false,"paint invalid "+r.uuid);quit(1);return
		editor._view.free()
		var frozen:=Prefab.bake(local);check(frozen.ok,"merged residential ground floor "+id)
		if not frozen.ok:quit(1);return
		var removed:Array=own.filter(func(r):return affected(r,old.parameters.base_height+old.position[1]))
		var previous:Dictionary={}
		for r:Dictionary in removed:previous[match_key(r)]=r;changed.append(r.uuid)
		check(previous.size()==removed.size(),"unique existing shell and fixture groups "+id)
		var origin:=Blueprint.vec(old.position);var basis:=Basis(Vector3.UP,deg_to_rad(old.yaw))
		var additions:Array=[]
		for r:Dictionary in frozen.records:
			var key:=match_key(r);var prior:Dictionary=previous.get(key,{})
			if prior.is_empty():
				r.uuid="obj_%d"%d._next;d._next+=1;r.building.part="main/residential_"+str(r.uuid)
			else:
				r.uuid=prior.uuid;r.building.part=prior.building.part
				if r.has("fixture"):r.fixture.open=prior.fixture.open
				for field in ["editor_name","editor_hidden","editor_group","editor_group_name","event_template","event"]:
					if prior.has(field):r[field]=prior[field]
			r.position=Blueprint.arr(origin+basis*Blueprint.vec(r.position));r.rotation=Blueprint.arr((basis*Basis.from_euler(Blueprint.vec(r.rotation)*PI/180)).get_euler()*180/PI)
			r.building.floor_y+=origin.y;r.building.id=id;r.editor_group=id;r.editor_group_name="东南桥 · 居民街"
			additions.append(r)
		var removed_ids:Array=removed.map(func(r):return r.uuid)
		d.records=d.records.filter(func(r):return r.uuid not in removed_ids);d.records.append_array(additions)
		old.parameters=parameters;old.parts={};old.signatures={};old.source_part_count=int(old.source_part_count)+local.size()-previous_source_count
		for r:Dictionary in d.records:
			if r.get("building",{}).get("id")==id:old.parts[r.building.part]=r.uuid;old.signatures[r.building.part]=Blueprint.geometry_signature(r)
		# The retained storeys still use their original source pieces. Record only
		# the conversion scope here instead of claiming a whole-house regeneration.
		merged.append({"id":id,"source_parts":local.size(),"frozen_groups":additions.size(),"replaced_groups":removed.size(),"window_style":parameters.window_style})
		converted.append(id);print("RESIDENTIAL_CONVERTED ",id," ",local.size()," -> ",additions.size());await process_frame
	for r:Dictionary in original:
		if r.uuid not in changed and not equivalent(r,d._find(r.uuid)):check(false,"unrelated record changed "+r.uuid)
	for id:String in original_meta.building_instances:
		if id not in converted and not equivalent(original_meta.building_instances[id],d.map_meta.building_instances[id]):check(false,"unrelated house changed "+id)
	var meta_before:Dictionary=original_meta.duplicate(true);meta_before.erase("building_instances")
	var meta_after:Dictionary=d.map_meta.duplicate(true);meta_after.erase("building_instances")
	check(equivalent(meta_before,meta_after),"roads, terrain, reserved areas and other metadata preserved")
	check(converted.size()==13 and p.houses.size()==26,"all 26 bridge-street residences; 13 shop conversions")
	check(p.houses.all(func(h):return d.map_meta.building_instances[h.id].parameters.template=="house"),"entire street residential")
	check(Blueprint.valid_ownership(d.map_meta,d.records),"native building ownership and floor/fixture validity")
	check(Paint.missing(d.records).is_empty(),"all surface dependencies available")
	var final:Array=d.records.duplicate(true);var final_meta:Dictionary=d.map_meta.duplicate(true)
	check(d.undo() and equivalent(d.records,original) and equivalent(d.map_meta,original_meta),"conversion batch undo")
	check(d.redo() and equivalent(d.records,final) and equivalent(d.map_meta,final_meta),"conversion batch redo")
	p.records=d.records;p.metadata=d.map_meta;p.next=d._next;p.failures=failed;p.formal_sha256=baseline;p.converted=converted;p.merged=merged;p.changed=changed
	for h:Dictionary in p.houses:h.position=d.map_meta.building_instances[h.id].position;h.use="居民住宅"
	FileAccess.open(OUT+"/plan.json",FileAccess.WRITE).store_string(JSON.stringify(p))
	print("RESIDENTIAL_PLAN failures=",failed);editor.free();quit(failed)
