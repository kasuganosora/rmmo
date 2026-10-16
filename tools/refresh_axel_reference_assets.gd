extends "res://tools/build_axel_town_houses.gd"
## Opt-in CPU authoring transaction. No screenshots, no terrain/road generation.
## --handoff=<json> --apply are both required to change the candidate.
## Handoff: candidate_sha256, template_path, template_sha256,
## assets:[{key:<existing prop key>,label:<formal catalog label>,sha256:<file SHA>}].
var receipt:Dictionary={"phase":"prepared","failures":0,"applied":false}
func write_json(path:String,value:Dictionary)->bool:
	var temporary:=path+".refresh.tmp"
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(value,"\t"));file.close()
	return DirAccess.rename_absolute(temporary,path)==OK
func finish_refresh(code:int)->void:
	receipt.failures=failed
	write_json(OUT+"/reference_asset_refresh.json",receipt)
	if is_instance_valid(editor):editor.queue_free()
	quit(code)
func run()->void:
	var handoff_path:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--handoff="):handoff_path=arg.trim_prefix("--handoff=")
	if handoff_path.is_empty():
		receipt.pending=["root-pinned post-water candidate SHA","explicit formal arch and relief labels/SHA","--apply authorization"]
		finish_refresh(0);return
	var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string(handoff_path))
	check(manifest is Dictionary,"handoff parses")
	if failed:finish_refresh(1);return
	var handoff:Dictionary=manifest
	check(FileAccess.get_sha256(CANDIDATE)==handoff.get("candidate_sha256",""),"exact post-water candidate pinned")
	check(FileAccess.get_sha256(str(handoff.get("template_path","")))==handoff.get("template_sha256",""),"replacement template SHA pinned")
	check(handoff.get("assets",[]).size()==2,"exactly arch and relief handoff entries required")
	report=data("build.json");recipe=data("housing_recipe.json")
	check(report.get("candidate_sha256","")==handoff.get("candidate_sha256",""),"build receipt belongs to the exact replacement candidate")
	var index:Dictionary=data("house_templates.json")
	var formal_before:=FileAccess.get_sha256(FORMAL)
	var index_before:=FileAccess.get_sha256(OUT+"/house_templates.json")
	var loaded:Dictionary={}
	if failed==0:loaded=JSON.parse_string(FileAccess.get_file_as_string(handoff.template_path))
	if loaded.is_empty():check(false,"replacement native template readable")
	var new_index:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(handoff.template_path).get_base_dir().get_base_dir()+"/house_templates.json"))
	var template_rows:Array=new_index.get("templates",[]).filter(func(t):return t.id=="s12_arch_hall")
	check(template_rows.size()==1,"single replacement template index row prepared before transaction")
	var catalog:=Props.catalog();var replacements:Dictionary={}
	for item:Dictionary in handoff.get("assets",[]):
		var key:String=item.get("key","")
		check(key.ends_with("/projecting_arch") or key.ends_with("/gable_relief"),"only approved S12 attachment keys")
		check(not replacements.has(key),"unique replacement key")
		var asset:=Props.entry(catalog,str(item.get("label","")))
		check(not asset.is_empty() and asset.has("asset_path"),"formal standalone asset exists "+key)
		if not asset.is_empty():check(FileAccess.get_sha256(str(asset.get("asset_path","")))==item.get("sha256",""),"formal asset SHA pinned "+key)
		replacements[key]=asset
	if failed:finish_refresh(1);return
	receipt.handoff=handoff;receipt.handoff_sha256=FileAccess.get_sha256(handoff_path)
	if "--apply" not in OS.get_cmdline_user_args():
		receipt.phase="inputs_verified_not_applied";finish_refresh(0);return
	var live=Doc.open_file(CANDIDATE)
	check(live!=null,"native candidate open")
	if failed:finish_refresh(1);return
	var before:Dictionary=live.recovery_snapshot()
	var staged=Doc.new();staged.apply_recovery(before)
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=staged;session.world3d_editor_path=CANDIDATE
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false;editor._draft_directory=OUT+"/reference_refresh_drafts"
	root.add_child(editor);await settle()
	check(editor._doc==staged,"native editor owns isolated transaction document")
	var matches:Array=report.houses.filter(func(h):return h.template_id=="s12_arch_hall")
	check(matches.size()==1,"exactly one S12 hall")
	if failed:finish_refresh(1);return
	var house:Dictionary=matches[0];var old_id:String=house.building_id
	var old_parts:Array=house.component_ids.duplicate()
	var old_native:Dictionary=staged.map_meta.building_instances.get(old_id,{})
	check(not old_native.is_empty(),"S12 native owner exists")
	check(B.valid_meta({"building_instances":loaded.building_instances}) and B.valid_ownership({"building_instances":loaded.building_instances},loaded.records),"new template preserves frozen ownership")
	check(loaded.building_instances.values()[0].parameters.get("front_string_course","")=="none","candidate suppresses only front stone course")
	if failed:finish_refresh(1);return
	# The old projecting attachments intersect their host intentionally. Remove
	# them natively on the isolated document before testing the new house shell.
	var attachment_originals:Dictionary={}
	for prop:Dictionary in report.props.placements:
		if not replacements.has(str(prop.key)):continue
		check(str(prop.key).begins_with(str(house.id)+"/"),"replacement belongs to S12 hall")
		var record:Dictionary=staged._find(str(prop.id))
		check(not record.is_empty() and editor._record_editable(record),"attachment is editable")
		attachment_originals[str(prop.id)]=record.duplicate(true)
	if failed:finish_refresh(1);return
	for id_:String in attachment_originals:check(staged.remove(id_),"native old attachment removal")
	var removed:Dictionary=editor._buildings.remove(old_id)
	check(removed.get("ok",false),"native delete_building on staged document")
	if failed:receipt.error=removed;finish_refresh(1);return
	var result:Dictionary=Library.place_buildings(staged,oriented(loaded,float(house.yaw)),B.vec(house.position),house.label)
	check(result.get("ok",false),"native frozen replacement placement")
	if failed:receipt.error=result;finish_refresh(1);return
	var new_id:String=staged._find(result.ids[0]).building.id
	house.building_id=new_id;house.component_ids=result.ids
	house.parameters=staged.map_meta.building_instances[new_id].parameters
	check(equivalent(old_native.position,staged.map_meta.building_instances[new_id].position) and is_equal_approx(float(old_native.yaw),float(staged.map_meta.building_instances[new_id].yaw)),"S12 origin and orientation unchanged")
	var actual:Dictionary={}
	for h:Dictionary in report.houses:actual[h.id]=h
	var requests:=Props.build_requests(staged,[data("house_plan_s1_s2.json"),data("house_plan_s10_s12.json")],actual)
	check(requests.get("ok",false),"current native attachment anchors available")
	var selected:Array=[];var removed_prop_ids:Array=[]
	for request:Dictionary in requests.get("requests",[]):
		var key:String=request.key
		if not replacements.has(key) and not key.ends_with("/redfruit"):continue
		var prior:Array=report.props.placements.filter(func(r):return r.key==key)
		check(prior.size()==1,"unique existing prop "+key)
		if prior.size()!=1:continue
		var record:Dictionary=attachment_originals.get(str(prior[0].id),staged._find(prior[0].id))
		check(not record.is_empty() and editor._record_editable(record),"prop editability "+key)
		if replacements.has(key):request.entry=replacements[key]
		selected.append(request);removed_prop_ids.append(prior[0].id)
	check(selected.size()==3,"two S12 attachments plus S10 fruit tree selected")
	if failed:finish_refresh(1);return
	for id_:String in removed_prop_ids:
		if not attachment_originals.has(id_):check(staged.remove(id_),"native old prop removal")
	var props:=Props.apply_requests(staged,{"ok":true,"requests":selected})
	check(props.get("ok",false),"native asset imports and pivot placement")
	if failed:receipt.error=props;finish_refresh(1);return
	# Library/Props batches write this native document directly. Publish their
	# complete record set to the same derived city state used by UI and MCP.
	editor._city.refresh()
	for fresh:Dictionary in props.placements:
		for i in report.props.placements.size():
			if report.props.placements[i].key==fresh.key:report.props.placements[i]=fresh
	report.props.ids=[]
	for prop:Dictionary in report.props.placements:report.props.ids.append(prop.id)
	staged.map_meta.town_reference.house_layout.placements=report.houses.duplicate(true)
	var allowed:Array=old_parts+removed_prop_ids
	for record:Dictionary in before.records:
		if record.uuid not in allowed:check(equivalent(record,staged._find(record.uuid)),"unrelated native record preserved "+str(record.uuid))
	for key:String in before.map_meta:
		if key not in ["building_instances","town_reference"]:check(equivalent(before.map_meta[key],staged.map_meta.get(key)),"unrelated metadata preserved "+key)
	check(B.valid_ownership(staged.map_meta,staged.records) and staged.validate_save()==OK,"replacement native save validation")
	if failed:finish_refresh(1);return
	var after:Dictionary=staged.recovery_snapshot()
	live.apply_recovery(after);live.commit_recovery_change(before)
	check(live.undo(),"single transaction undo")
	var undo_state:Dictionary=live.recovery_snapshot();undo_state.erase("next")
	var baseline:Dictionary=before.duplicate(true);baseline.erase("next")
	check(equivalent(baseline,undo_state),"undo restores all original content")
	check(live.redo() and equivalent(after,live.recovery_snapshot()),"single transaction redo exact")
	check(FileAccess.get_sha256(CANDIDATE)==handoff.candidate_sha256 and FileAccess.get_sha256(OUT+"/house_templates.json")==index_before,"no concurrent candidate/index writer")
	if failed:finish_refresh(1);return
	check(live.save(CANDIDATE)==OK,"native atomic candidate save")
	var reopened=Doc.open_file(CANDIDATE)
	check(reopened!=null and equivalent(live.records,reopened.records) and equivalent(live.map_meta,reopened.map_meta),"native candidate reopen exact")
	if failed:receipt.phase="saved_reopen_failed";finish_refresh(1);return
	for i in index.templates.size():
		if index.templates[i].id=="s12_arch_hall":index.templates[i]=template_rows[0]
	check(write_json(OUT+"/house_templates.json",index),"atomic single-template source reference update")
	# Pin only versions actually consumed by this refresh; retain old recipe pin.
	for name_:String in ["house_templates.json","house_plan_s1_s2.json","house_plan_s10_s12.json"]:report.authoring_inputs[name_]=FileAccess.get_sha256(OUT.path_join(name_))
	report.reference_asset_handoff={"path":handoff_path,"sha256":FileAccess.get_sha256(handoff_path)}
	report.candidate_sha256=FileAccess.get_sha256(CANDIDATE);report.phase="reference_assets_refreshed";report.failures=failed
	check(FileAccess.get_sha256(FORMAL)==formal_before,"formal map untouched")
	check(write_json(OUT+"/build.json",report),"build receipt updated")
	receipt.phase="saved_and_reopened";receipt.applied=true;receipt.old_building_id=old_id;receipt.new_building_id=new_id
	receipt.candidate_sha256=report.candidate_sha256;receipt.props=props;receipt.visual="pending GPU review"
	finish_refresh(1 if failed else 0)
