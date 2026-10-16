extends "res://tools/test_world3d_mcp.gd"
## Explicit native whole-group replacement, not unfreezing a baked structure.
## Default stages only. --apply saves the SHA-pinned wall-only cache candidate.
const City=preload("res://scripts/world3d/city_layout.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Tangents=preload("res://scripts/world3d/mesh_tangent_repair.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const FORMAL="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const RECEIPT=OUT+"/fortification_build.json"
const OWNER="axel_city_fortification"
var target:= "D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf"
var output:=OUT+"/fortification_regeneration.json"
var expected_sha:=""
var apply_requested:=false
var report:Dictionary={"saved":false,"native_reopen_passed":false,"phase":"starting","operations":[],"method":"native remove_fortification(keep_objects=false), then preview_fortification/generate_fortification in private staging"}
var pins:Dictionary={}
var build:Dictionary={}
var checks:=0

func check(ok:bool,label:String)->void:
	checks+=1;super.check(ok,label)
func canonical(path:String)->String:return ProjectSettings.globalize_path(path).replace("\\","/").simplify_path().to_lower()
func identity(snapshot:Dictionary)->Dictionary:return {"records":snapshot.records,"map_meta":snapshot.map_meta}
func digest(value:Variant)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(var_to_bytes(value));return hash.finish().hex_encode()
func pin(path:String,expected:String="")->bool:
	check(FileAccess.file_exists(path),"required file exists: "+path.get_file())
	if not FileAccess.file_exists(path):return false
	var actual:=FileAccess.get_sha256(path)
	check(expected.is_empty() or actual==expected,"exact input identity: "+path.get_file())
	if not expected.is_empty() and actual!=expected:return false
	pins[path]=actual;return true
func read_json(path:String)->Dictionary:
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(data is Dictionary,"valid JSON: "+path.get_file());return data if data is Dictionary else {}
func atomic_bytes(path:String,bytes:PackedByteArray)->bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path+".pending",FileAccess.WRITE)
	if file==null:check(false,"write artifact "+path);return false
	file.store_buffer(bytes);file.close()
	var ok:=Atomic.publish(path+".pending",path)==OK;check(ok,"atomic artifact "+path.get_file());return ok
func immutable(bytes:PackedByteArray)->Dictionary:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	var sha:=hash.finish().hex_encode();var path:=OUT+"/fortification_history/"+sha+".json"
	if not FileAccess.file_exists(path):atomic_bytes(path,bytes)
	check(FileAccess.file_exists(path) and FileAccess.get_sha256(path)==sha,"immutable receipt preserves exact bytes")
	return {"path":path,"sha256":sha}
func persist()->void:
	report.failures=failed;report.checks=checks;report.apply=apply_requested;report.inputs=pins
	var file:=FileAccess.open(output+".pending",FileAccess.WRITE)
	if file==null:push_error("Cannot write regeneration report");failed+=1;return
	file.store_string(JSON.stringify(report,"\t"));file.close()
	if Atomic.publish(output+".pending",output)!=OK:failed+=1
func stopped()->bool:
	if failed==0:return false
	report.phase="failed_after_candidate_save" if report.saved else "blocked_without_candidate_save";persist()
	if is_instance_valid(editor) and editor._mcp!=null:editor._mcp.stop()
	quit(1);return true
func operation(name_:String,args:Dictionary)->Dictionary:
	report.phase=name_;persist()
	var result:=await call_tool(name_,args)
	report.operations.append({"tool":name_,"request":args,"result":result});persist();return result
func region(metadata:Dictionary)->Dictionary:
	var found:Array=City.resolve(metadata).get("fortifications",[]).filter(func(item):return item.settings.id==OWNER)
	return found[0] if found.size()==1 else {}
func stage_guard(metadata:Dictionary)->void:
	var reference:Dictionary=metadata.get("town_reference",{})
	for key:String in reference:
		check(not (key.contains("market") or key.contains("functional") or key.contains("vegetation")),"later layout metadata absent: "+key)
	for filename:String in ["market_build.json","functional_buildings_apply.json","functional_vegetation_build.json"]:
		var path:=OUT+"/"+filename
		if not FileAccess.file_exists(path):continue
		var receipt:=read_json(path)
		check(not receipt.get("saved",false),"later native stage has not saved: "+filename)
func ordinary_metadata(metadata:Dictionary)->Dictionary:
	var result:=metadata.duplicate(true);result.editor_layout.fortifications=[];return result
func outside_group(records:Array)->Dictionary:
	var result:Dictionary={}
	for item:Dictionary in records:
		if item.get("fortification",{}).get("id","")!=OWNER:result[item.uuid]=item
	return result
func normal_required(data:Dictionary,mesh_index:int,surface_index:int)->bool:
	var material:Dictionary=data.materials[int(data.meshes[mesh_index].materials[surface_index])]
	if material.has("paint"):
		return not str(material.paint.get("normal_path","")).is_empty() and float(material.paint.get("normal_strength",1.))>0.
	# Non-paint StandardMaterial snapshots contain plain stored properties.
	# A normal-enabled flag without an actual normal texture consumes no basis.
	var values:Dictionary=material.get("values",{})
	return values.get("normal_enabled",false) and values.get("normal_texture")!=null and float(values.get("normal_scale",1.))>0.
func compare_frozen(old:Dictionary,current:Dictionary)->Dictionary:
	var a:=old.duplicate(true);var b:=current.duplicate(true);a.erase("house_prefab");b.erase("house_prefab")
	var result:Dictionary={"id":old.uuid,"before_sha256":old.house_prefab.sha256,"after_sha256":current.get("house_prefab",{}).get("sha256",""),"surfaces":0,"normal_mapped_render_surfaces":0,"vertices":0,"changed_tangent_values":0,"invalid_after":0,"valid_tangents_changed":0,"non_tangent_data_identical":false,"unchanged_channels_scope":"all geometry/UV/normals/index/material/LOD, all collision channels and non-normal-mapped render tangents"}
	check(current.has("house_prefab"),"regenerated component retains frozen payload: "+str(old.uuid))
	if failed:return result
	check(City.token(a)==City.token(b),"only frozen payload may change: "+str(old.uuid))
	check(Frozen.valid(old) and Frozen.valid(current),"native frozen payload identities valid: "+str(old.uuid))
	if failed:return result
	var left:=Frozen.decode(old.house_prefab);var right:=Frozen.decode(current.house_prefab)
	check(not left.is_empty() and not right.is_empty() and left.meshes.size()==right.meshes.size(),"same frozen mesh count: "+str(old.uuid))
	if failed:return result
	var render_meshes:Dictionary={}
	for entry:Array in right.entries:render_meshes[int(entry[1][0])]=true
	for mi:int in left.meshes.size():
		check(left.meshes[mi].surfaces.size()==right.meshes[mi].surfaces.size(),"same frozen surface count: "+str(old.uuid)+"/"+str(mi))
		if failed:return result
		for si:int in left.meshes[mi].surfaces.size():
			var la:Array=left.meshes[mi].surfaces[si];var ra:Array=right.meshes[mi].surfaces[si]
			var consumes_tangents:=render_meshes.has(mi) and normal_required(right,mi,si)
			var old_t:PackedFloat32Array=la[Mesh.ARRAY_TANGENT] if la[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
			var new_t:PackedFloat32Array=ra[Mesh.ARRAY_TANGENT] if ra[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
			var vertices:PackedVector3Array=ra[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=ra[Mesh.ARRAY_NORMAL] if ra[Mesh.ARRAY_NORMAL]!=null else PackedVector3Array()
			var indices:PackedInt32Array=ra[Mesh.ARRAY_INDEX] if ra[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var referenced:Dictionary={};var count:int=indices.size() if not indices.is_empty() else vertices.size()
			# Source collision meshes intentionally contain positions only. Their
			# complete bytes remain in the non-tangent identity comparison below.
			for ti:int in range(0,count-2,3) if consumes_tangents else []:
				var i0:int=indices[ti] if not indices.is_empty() else ti;var i1:int=indices[ti+1] if not indices.is_empty() else ti+1;var i2:int=indices[ti+2] if not indices.is_empty() else ti+2
				if (vertices[i1]-vertices[i0]).cross(vertices[i2]-vertices[i0]).length_squared()>0.:
					referenced[i0]=true;referenced[i1]=true;referenced[i2]=true
			result.surfaces+=1;result.vertices+=vertices.size()
			if consumes_tangents:result.normal_mapped_render_surfaces+=1
			if new_t.size()!=vertices.size()*4:result.invalid_after+=referenced.size()
			else:
				for vi:int in referenced:
					var t:=Vector3(new_t[vi*4],new_t[vi*4+1],new_t[vi*4+2])
					if normals.size()!=vertices.size() or Tangents.invalid(t,new_t[vi*4+3],normals[vi]):result.invalid_after+=1
			if consumes_tangents and old_t.size()==new_t.size():
				for vi:int in range(0,new_t.size(),4):
					var changed:=false
					for c:int in 4:
						if old_t[vi+c]!=new_t[vi+c]:result.changed_tangent_values+=1;changed=true
					var ot:=Vector3(old_t[vi],old_t[vi+1],old_t[vi+2]);var vertex:int=vi/4
					if changed and normals.size()>vertex and not Tangents.invalid(ot,old_t[vi+3],normals[vertex]):result.valid_tangents_changed+=1
			if consumes_tangents:la[Mesh.ARRAY_TANGENT]=null;ra[Mesh.ARRAY_TANGENT]=null
	# Exact authored geometry, UVs, normals, indices, materials, entries and LODs.
	result.non_tangent_data_identical=digest(left)==digest(right)
	check(result.non_tangent_data_identical,"geometry/UV/normal/material/LOD/collision source unchanged: "+str(old.uuid))
	check(result.invalid_after==0 and result.valid_tangents_changed==0,"valid surface tangents preserved and invalid used vertices repaired: "+str(old.uuid))
	return result
func final_pins()->void:
	for path:String in pins:check(FileAccess.get_sha256(path)==pins[path],"input unchanged: "+path.get_file())
	check(FileAccess.get_sha256(target)==expected_sha,"candidate unchanged until native atomic save")
	check(FileAccess.get_sha256(FORMAL)==report.source_sha256,"formal source unchanged")

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--apply":apply_requested=true
		elif arg.begins_with("--map="):target=arg.trim_prefix("--map=")
		elif arg.begins_with("--expected-sha="):expected_sha=arg.trim_prefix("--expected-sha=")
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	check(Paths.allowed(output) and output.get_extension()=="json" and canonical(output)!=canonical(RECEIPT),"separate regeneration report in content root")
	check(canonical(target).begins_with("d:/code/rmmo_runtime/cache/world3d/") and canonical(target)!=canonical(FORMAL),"cache candidate only")
	if not pin(RECEIPT):stopped();return
	build=read_json(RECEIPT)
	check(build.get("saved",false) and build.get("apply",false) and build.get("failures",-1)==0 and build.get("phase","")=="native_candidate_complete_review_pending","previous native wall stage completed")
	check(expected_sha.length()==64 and expected_sha==build.get("candidate_sha256","") and canonical(target)==canonical(build.get("candidate","")),"explicit input matches current wall receipt")
	pin(target,expected_sha);pin(FORMAL,str(build.get("source_sha256","")));pin(str(build.get("plan_path","")),str(build.get("plan_sha256","")))
	if build.has("relocation_plan"):pin(build.relocation_plan.path,build.relocation_plan.sha256)
	for path:String in ["res://scripts/world3d/mesh_tangent_repair.gd","res://scripts/world3d/fortification_art.gd","res://scripts/world3d/fortification_terrain.gd","res://scripts/world3d/runtime_mesh_cache.gd","res://scripts/world_editor/fortification_tools.gd","res://scripts/world3d/house_prefab.gd","res://scripts/world3d/structure_prefab.gd"]:pin(ProjectSettings.globalize_path(path))
	if stopped():return
	report.merge({"map":target,"input_sha256":expected_sha,"source":FORMAL,"source_sha256":build.source_sha256,"previous_build_sha256":pins[RECEIPT],"model_review":"affected frozen tangent channels only; parent owns actual final images/resource acceptance"})
	var original=Doc.open_file(target);check(original!=null,"actual wall candidate opens natively")
	if stopped():return
	var before:Dictionary=original.recovery_snapshot();stage_guard(before.map_meta)
	var old_region:=region(before.map_meta)
	check(not old_region.is_empty() and old_region.get("baked",false) and City.resolve(before.map_meta).fortifications.size()==1,"one existing frozen target fortification")
	if stopped():return
	check(City.token(old_region.settings)==City.token(build.preview.settings),"same saved and initial preview settings")
	var request:Dictionary=old_region.settings.duplicate(true);request.erase("layout_version")
	report.settings_token=City.token(old_region.settings);report.request=request
	if stopped():return
	rpc_timeout_ms=600000;create_timer(2400).timeout.connect(func():check(false,"regeneration timeout");persist();quit(2))
	var fixture:=OUT+"/fortification_regeneration_fixture/map.gltf";DirAccess.make_dir_recursive_absolute(fixture.get_base_dir())
	var empty:=Doc.new();check(empty.save(fixture)==OK,"native empty startup fixture")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=fixture;session.world3d_editor_doc=empty
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=OUT+"/fortification_regeneration_drafts";root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var staged:=Doc.new();staged.apply_recovery(before);editor._doc=staged;editor._city.refresh();editor._authoring.refresh()
	var listener:=TCPServer.new();port=33870
	while listener.listen(port,"127.0.0.1")!=OK:port+=1
	listener.stop();check(editor.start_mcp(port).ok,"current 3D loopback MCP")
	var discovery:=await rpc("tools/list");var names:Array=discovery.get("result",{}).get("tools",[]).map(func(t):return t.name)
	check(["remove_fortification","preview_fortification","generate_fortification"].all(func(name_):return names.has(name_)),"native whole-group replacement tools discovered")
	if stopped():return
	await operation("remove_fortification",{"id":OWNER,"keep_objects":false})
	if stopped():return
	check(outside_group(before.records)==outside_group(staged.records) and region(staged.map_meta).is_empty(),"native removal touches only owned wall group")
	var preview:=await operation("preview_fortification",request)
	if stopped():return
	check(City.token(preview.settings)==City.token(old_region.settings),"regeneration preview retains exact saved settings")
	for key:String in ["gates","access_routes","outline"]:check(City.token(preview.get(key,[]))==City.token(build.preview.get(key,[])),"same fitted world-space "+key)
	if stopped():return
	request.plan_token=preview.plan_token;var generated:=await operation("generate_fortification",request)
	if stopped():return
	var new_region:=region(staged.map_meta);check(City.token(new_region.settings)==City.token(old_region.settings),"new frozen group settings unchanged")
	report.preservation={"non_fortification_records_identical":outside_group(before.records)==outside_group(staged.records),"non_fortification_metadata_identical":City.token(ordinary_metadata(before.map_meta))==City.token(ordinary_metadata(staged.map_meta))}
	check(report.preservation.non_fortification_records_identical,"all terrain/roads/grass/houses/water/other records exact identity")
	check(report.preservation.non_fortification_metadata_identical,"only fortification ownership signatures change; all other metadata exact")
	var old_ids:Array=old_region.parts.map(func(p):return p.id);var new_ids:Array=new_region.parts.map(func(p):return p.id);old_ids.sort();new_ids.sort()
	report.preservation.component_ids_stable=old_ids==new_ids
	check(report.preservation.component_ids_stable,"all native frozen component UUIDs stable")
	if stopped():return
	report.frozen_comparison=[];var changed:=0
	for id:String in old_ids:
		var old:Dictionary=original._find(id);var current:Dictionary=staged._find(id)
		if not old.has("house_prefab"):
			check(City.token(old)==City.token(current),"independent non-frozen fixture unchanged: "+id)
			if failed:break
			continue
		var row:=compare_frozen(old,current);report.frozen_comparison.append(row)
		if row.before_sha256!=row.after_sha256:changed+=1
		if failed:break
	check(changed>0,"at least one actual frozen payload changed")
	report.changed_frozen_components=changed;report.preview=preview;report.generated=generated
	check(staged.validate_save()==OK,"native staged document validates")
	if stopped():return
	var after:Dictionary=staged.recovery_snapshot();var undo_count:int=original._undo.size();original.apply_recovery(after);original.commit_recovery_change(before)
	report.transaction={"undo_passed":original.undo() and City.token(identity(original.recovery_snapshot()))==City.token(identity(before))}
	check(report.transaction.undo_passed,"one outer native undo restores initial frozen group and metadata")
	report.transaction.redo_passed=original.redo() and City.token(identity(original.recovery_snapshot()))==City.token(identity(after))
	check(report.transaction.redo_passed,"one outer native redo restores regenerated group")
	check(original._undo.size()==mini(undo_count+1,32) and original._next>=int(before.next),"history retained and object counter monotonic")
	check(original._disk_signature==expected_sha,"native candidate disk conflict signature retained")
	final_pins();stage_guard(original.map_meta)
	if stopped():return
	report.phase="native_regeneration_preflight_passed";persist()
	if not apply_requested:editor._mcp.stop();quit(0);return
	# Preserve the exact prior receipt before any map write. No map backup copy.
	report.previous_build=immutable(FileAccess.get_file_as_bytes(RECEIPT))
	report.initial_build=build.get("initial_build",report.previous_build)
	if stopped():return
	check(original.save(target)==OK,"native atomic conflict-aware wall candidate save")
	if stopped():return
	report.saved=true;report.output_sha256=FileAccess.get_sha256(target);persist()
	var reopened=Doc.open_file(target)
	report.native_reopen_passed=reopened!=null and reopened.validate_save()==OK and City.token(identity(reopened.recovery_snapshot()))==City.token(identity(after))
	check(report.native_reopen_passed,"native save/reopen retains complete regenerated state")
	report.transaction.save_reopen=report.native_reopen_passed
	check(FileAccess.get_sha256(FORMAL)==report.source_sha256 and FileAccess.get_sha256(RECEIPT)==pins[RECEIPT],"formal and previous receipt untouched during candidate save")
	if stopped():return
	report.phase="native_fortification_regeneration_complete_review_pending";persist()
	var proof:=immutable(FileAccess.get_file_as_bytes(output))
	if stopped():return
	var updated:=build.duplicate(true);updated.initial_build=report.initial_build
	if not updated.has("regenerations"):updated.regenerations=[]
	updated.regenerations.append(proof.merged({"input_sha256":expected_sha,"output_sha256":report.output_sha256,"method":report.method}))
	updated.candidate_sha256=report.output_sha256;updated.native_reopen_passed=true
	updated.latest_regeneration=proof;updated.visual="pending regenerated tangent review";updated.runtime="pending current candidate"
	updated.history_note="Initial native construction remains in initial_build and original operations. Regenerations append explicit native whole-group replacement evidence."
	atomic_bytes(RECEIPT,JSON.stringify(updated,"\t").to_utf8_buffer())
	check(FileAccess.get_sha256(target)==report.output_sha256,"final candidate unchanged after receipt update")
	# The immutable completed proof is deliberately not rewritten after linking.
	editor._mcp.stop();quit(0 if failed==0 else 1)
