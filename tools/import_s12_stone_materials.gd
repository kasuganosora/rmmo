extends "res://tools/import_s2_green_post.gd"
## Two reviewed material revisions replace the two existing S12 library entries.
## Old immutable assets remain available to existing maps. No map is edited.
## --plan=<JSON> --plan-sha256=<SHA> --out=<fresh JSON> --publish
## Optional --resume-receipt=<failed receipt> only resumes its exact staged imports.
const LEGACY:Dictionary={
	"s12_projecting_arch":{"file":"11feb4a7d18c9fd25cef5ca588e55f1e518141b78acc5baaf3b1a048920f43be.glb","label":"S12 外挑双柱大拱门"},
	"s12_gable_relief":{"file":"d0ca66d5b04913d4bc9ffd56fcc01bb2f4761332dc28fcd98337ad21026dd240.glb","label":"S12 山墙高窄雕饰板"}
}
var replacements:Array=[]
var resume_staged:Dictionary={}

static func same_material_evidence(actual:Variant,expected:Variant,field:String="")->bool:
	# JSON parses integer counts/enums as floats. Compare exact numeric values,
	# never an epsilon. Material scalar properties live in float32; Godot JSON
	# may parse their decimal representation one float64 ULP away (documented
	# in the guard diagnostic), so compare their exact native float32 bits.
	var actual_number:bool=actual is int or actual is float
	var expected_number:bool=expected is int or expected is float
	if actual_number or expected_number:
		if not actual_number or not expected_number:return false
		if field in ["metallic","roughness","normal_scale"]:return PackedFloat32Array([actual]).to_byte_array()==PackedFloat32Array([expected]).to_byte_array()
		return float(actual)==float(expected)
	if typeof(actual)!=typeof(expected):return false
	if actual is Array:
		if actual.size()!=expected.size():return false
		for i in actual.size():
			if not same_material_evidence(actual[i],expected[i],field):return false
		return true
	if actual is Dictionary:
		if actual.size()!=expected.size():return false
		for key in actual:
			if not expected.has(key) or not same_material_evidence(actual[key],expected[key],str(key)):return false
		return true
	return actual==expected

static func texture_pixels(texture:Texture2D)->Dictionary:
	if texture==null:return {}
	var img:=texture.get_image()
	if img==null:return {"invalid":true}
	if img.is_compressed() and img.decompress()!=OK:return {"invalid":true}
	img.clear_mipmaps();img.convert(Image.FORMAT_RGBA8)
	var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(img.get_data())
	return {"size":[img.get_width(),img.get_height()],"rgba_base_sha256":hashing.finish().hex_encode()}

static func actual_material_snapshot(scene:Node,id:String)->Dictionary:
	var result:Dictionary={"ok":true,"actual_materials":[]}
	for node:MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
		for slot in node.mesh.get_surface_count():
			var mat:=node.get_active_material(slot) as StandardMaterial3D
			if mat==null:result.ok=false;continue
			var arrays:=node.mesh.surface_get_arrays(slot)
			var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
			var stone:bool=id=="s12_gable_relief" or (str(node.name).ends_with("_part_0") and slot==0)
			if stone and (not mat.normal_enabled or mat.normal_texture==null or mat.emission_enabled or mat.metallic!=0):result.ok=false
			if tangents.is_empty():result.ok=false
			result.actual_materials.append({"node":str(node.name),"surface":slot,"material_name":mat.resource_name,"stone_surface":stone,"albedo_color":var_to_str(mat.albedo_color),"metallic":mat.metallic,"roughness":mat.roughness,"roughness_channel":mat.roughness_texture_channel,"ao_enabled":mat.ao_enabled,"ao_channel":mat.ao_texture_channel,"normal_enabled":mat.normal_enabled,"normal_scale":mat.normal_scale,"normal":texture_pixels(mat.normal_texture),"albedo":texture_pixels(mat.albedo_texture),"roughness_map":texture_pixels(mat.roughness_texture),"ao_map":texture_pixels(mat.ao_texture),"tangent_floats":tangents.size()})
	if result.actual_materials.is_empty():result.ok=false
	return result

func parse_options()->bool:
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--publish" and not options.has("publish"):options.publish=true;continue
		if not arg.begins_with("--") or not arg.contains("="):return check(false,"expected unique --key=value")
		var key:=arg.substr(2).get_slice("=",0)
		if key not in ["plan","plan-sha256","out","resume-receipt"] or options.has(key):return check(false,"known unique argument "+key)
		options[key]=arg.substr(arg.find("=")+1)
	for key:String in ["plan","plan-sha256","out"]:
		if not check(not str(options.get(key,"")).is_empty(),"required "+key):return false
	for key:String in ["plan","out","resume-receipt"]:
		if options.has(key):options[key]=canonical(options[key])
	var confined:bool=Paths.allowed(options.out,canonical("res://review_artifacts")) or Paths.allowed(options.out,Paths.external_root().path_join("review_artifacts"))
	if not check(confined and str(options.out).get_extension()=="json" and not FileAccess.file_exists(options.out) and not FileAccess.file_exists(str(options.out)+".tmp"),"fresh confined output receipt"):return false
	output=options.out
	return true

func raw_catalog(folder:String)->Dictionary:
	var path:=folder.path_join("library.json");var digest:=FileAccess.get_sha256(path)
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Array:return {"ok":false,"error":"catalog root is not an array"}
	for entry:Variant in value:
		if not entry is Dictionary or not entry.get("label") is String or not entry.get("category") is String:return {"ok":false,"error":"catalog contains malformed entry metadata"}
		if not (entry.get("asset_path") is String or entry.get("prefab_path") is String):return {"ok":false,"error":"catalog entry has no typed source path"}
		for key:String in ["asset_path","prefab_path","thumbnail_path"]:
			if not entry.has(key):continue
			if not entry[key] is String or str(entry[key]).is_empty() or str(entry[key]).is_absolute_path():return {"ok":false,"error":"catalog disk path is not relative: "+key}
			var resolved:=canonical(folder.path_join(entry[key]))
			if not Paths.allowed(resolved):return {"ok":false,"error":"catalog relative path escapes content root"}
			# Refuse a spelling that normal Library.save would rewrite on an
			# unrelated entry (including outside-folder relative dependencies).
			if not resolved.begins_with(folder+"/") or resolved.trim_prefix(folder+"/")!=entry[key]:return {"ok":false,"error":"relative path would change during ordinary catalog roundtrip"}
	if FileAccess.get_sha256(path)!=digest:return {"ok":false,"error":"catalog changed during raw read"}
	return {"ok":true,"entries":value,"sha256":digest}

func resolve_entry(entry:Dictionary,folder:String)->Dictionary:
	var result:=entry.duplicate(true)
	for key:String in ["asset_path","prefab_path","thumbnail_path"]:
		if result.get(key) is String and not str(result[key]).is_absolute_path():result[key]=canonical(folder.path_join(result[key]))
	return result

func matches_path(entries:Array,path:String)->Array:
	return entries.filter(func(entry):return entry is Dictionary and entry.get("asset_path")==path)

func replacement_snapshot(current:Array,rows:Array,staged:Dictionary)->Dictionary:
	# Pure transaction builder. Never modifies the passed snapshot. Only the
	# two exact old entries and this receipt's exact staged entries are writable.
	var by_old:Dictionary={};var staged_paths:Dictionary={};var items:Array=[]
	for row:Dictionary in rows:
		if not staged.get(row.id) is Dictionary:return {"ok":false,"error":"missing staged import"}
		var stage:Dictionary=staged[row.id].get("entry",{})
		var old:Array=matches_path(current,row.old_asset_path);var new_:Array=matches_path(current,row.target)
		if old.size()!=1 or new_.size()!=1:return {"ok":false,"error":"old/staged entry is missing or duplicated"}
		if not same_entry(old[0],row.old_entry) or not same_entry(new_[0],stage):return {"ok":false,"error":"old or staged entry changed independently"}
		if current.filter(func(entry):return entry.get("label")==row.old_entry.label).size()!=1:return {"ok":false,"error":"original label is ambiguous"}
		var desired:Dictionary=row.old_entry.duplicate(true)
		for key:String in ["asset_path","thumbnail_path","bounds_position","bounds_size"]:
			if not stage.has(key):return {"ok":false,"error":"staged asset lacks "+key}
			desired[key]=stage[key]
		by_old[row.old_asset_path]=desired;staged_paths[row.target]=true
		items.append({"id":row.id,"old_asset_path":row.old_asset_path,"old_entry":row.old_entry.duplicate(true),"entry":desired.duplicate(true),"source_path":row.source_path,"target":row.target,"sha256":row.source_sha256,"label":desired.label,"category":desired.category,"acceptance_report":row.review_path,"acceptance_report_sha256":row.review_sha256})
	var next:Array=[]
	for entry:Dictionary in current:
		var path:String=str(entry.get("asset_path",""))
		if staged_paths.has(path):continue
		next.append(by_old.get(path,entry).duplicate(true))
	if next.size()!=current.size()-rows.size():return {"ok":false,"error":"unexpected catalog count delta"}
	return {"ok":true,"entries":next,"items":items}

func entry_guard_self_test()->void:
	var accepted_path:="res://review_artifacts/s12_stone_materials_20261015/v2/arch/report.json"
	if FileAccess.file_exists(accepted_path):
		var accepted:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(accepted_path))
		for diagnostic:Array in [["normal_scale",PackedFloat32Array([.12])[0],accepted.actual_materials[0].normal_scale],["roughness",PackedFloat32Array([.55])[0],accepted.actual_materials[1].roughness]]:
			var a:=PackedFloat64Array([diagnostic[1]]).to_byte_array().hex_encode()
			var e:=PackedFloat64Array([diagnostic[2]]).to_byte_array().hex_encode()
			print("MATERIAL_NUMBER_DIAGNOSTIC ",diagnostic[0]," live=",var_to_str(diagnostic[1])," parsed=",var_to_str(diagnostic[2])," live64=",a," parsed64=",e," float32_equal=",PackedFloat32Array([diagnostic[1]])[0]==PackedFloat32Array([diagnostic[2]])[0])
			check(same_material_evidence(diagnostic[1],diagnostic[2],diagnostic[0]),"accepted material scalar matches exact native float32 bits "+diagnostic[0])
	var live_material:Dictionary={"surface":0,"normal_scale":0.11999999731779099,"normal":{"size":[2048,2048],"rgba_base_sha256":"exact"},"normal_enabled":true}
	var parsed_material:Dictionary=JSON.parse_string(JSON.stringify(live_material))
	check(same_material_evidence(live_material,parsed_material),"live material integer fields compare exactly with JSON numeric fields")
	var changed_material:=parsed_material.duplicate(true)
	var bits:=PackedFloat32Array([live_material.normal_scale]).to_byte_array()
	bits.encode_u32(0,bits.decode_u32(0)+1);changed_material.normal_scale=bits.decode_float(0)
	check(not same_material_evidence(live_material,changed_material),"one native float32 ULP change in material scalar is rejected")
	changed_material=parsed_material.duplicate(true);changed_material.surface+=.000000000001
	check(not same_material_evidence(live_material,changed_material),"nonmaterial numeric values have no epsilon tolerance")
	changed_material=parsed_material.duplicate(true);changed_material.normal.rgba_base_sha256="different"
	check(not same_material_evidence(live_material,changed_material),"material texture pixel SHA remains exact")
	changed_material=parsed_material.duplicate(true);changed_material.normal_enabled=1
	check(not same_material_evidence(live_material,changed_material),"material boolean does not equal numeric one")
	changed_material=parsed_material.duplicate(true);changed_material.extra=true
	check(not same_material_evidence(live_material,changed_material),"material evidence key set remains exact")
	var old_a:Dictionary={"asset_path":"D:/fixture/old_a.glb","thumbnail_path":"D:/fixture/old_a.png","label":"old A","category":"stone","bounds_position":[-.31882554292678833,0.,0.],"bounds_size":[.6519860625267029,3.063523054122925,.5668175220489502],"author":"retain"}
	var old_b:=old_a.duplicate(true);old_b.asset_path="D:/fixture/old_b.glb";old_b.label="old B"
	var new_a:=old_a.duplicate(true);new_a.asset_path="D:/fixture/new_a.glb";new_a.thumbnail_path="D:/fixture/new_a.png";new_a.label="runtime_a";new_a.erase("author")
	var new_b:=new_a.duplicate(true);new_b.asset_path="D:/fixture/new_b.glb";new_b.thumbnail_path="D:/fixture/new_b.png";new_b.label="runtime_b"
	var other:Dictionary={"prefab_path":"D:/fixture/other.gltf","label":"unrelated","category":"unchanged","bounds_size":[1.,2.,3.]}
	var rows:Array=[]
	for pair:Array in [["a",old_a,new_a],["b",old_b,new_b]]:
		rows.append({"id":pair[0],"old_asset_path":pair[1].asset_path,"old_entry":pair[1],"target":pair[2].asset_path,"source_path":"D:/fixture/source.glb","source_sha256":"fixture","review_path":"D:/fixture/review.json","review_sha256":"fixture"})
	var staged:Dictionary={"a":{"entry":new_a},"b":{"entry":new_b}}
	var current:Array=[old_a,other,old_b,new_a,new_b]
	var before:=current.duplicate(true)
	var result:=replacement_snapshot(current,rows,staged)
	check(result.ok and result.entries.size()==3,"transaction replaces two old entries and removes only two staged entries")
	check(current==before,"pure transaction leaves input snapshot unchanged")
	check(result.entries[1]==other,"unrelated prefab metadata and original order preserved")
	check(result.entries[0].label==old_a.label and result.entries[2].label==old_b.label and result.entries[0].author=="retain","old labels and nonasset metadata preserved")
	var roundtrip:Array=JSON.parse_string(JSON.stringify(current))
	check(replacement_snapshot(roundtrip,rows,staged).ok,"only bounds JSON roundtrip is tolerated")
	var concurrent:=current.duplicate(true);concurrent.append({"asset_path":"D:/fixture/concurrent.glb","label":"new concurrent asset","category":"user"})
	check(replacement_snapshot(concurrent,rows,staged).entries.back()==concurrent.back(),"concurrent unrelated addition preserved")
	var edited:=current.duplicate(true);edited[0].label="someone renamed A"
	check(not replacement_snapshot(edited,rows,staged).ok,"independent old-target rename rejected")
	edited=current.duplicate(true);edited[3].category="user edited staged"
	check(not replacement_snapshot(edited,rows,staged).ok,"independent staged-entry edit rejected")
	edited=current.duplicate(true);edited[0].bounds_size[0]+=.000001
	check(not replacement_snapshot(edited,rows,staged).ok,"real target bounds edit rejected")
	edited=current.duplicate(true);edited[0].extra=true
	check(not replacement_snapshot(edited,rows,staged).ok,"target key-set change rejected")
	edited=current.duplicate(true);edited.append(old_a.duplicate(true))
	check(not replacement_snapshot(edited,rows,staged).ok,"duplicate original entry rejected")
	edited=current.duplicate(true);edited.append({"asset_path":"D:/fixture/conflict.glb","label":old_a.label,"category":"user"})
	check(not replacement_snapshot(edited,rows,staged).ok,"same-name ambiguity rejected")
	print("S12_STONE_ENTRY_GUARDS checks=",audit.checks.size()," failures=",audit.failures.size())
	quit(0 if audit.failures.is_empty() else 1)

func prepare_plan(folder:String)->bool:
	if not check(Compile._sha(options["plan-sha256"]) and FileAccess.get_sha256(options.plan)==options["plan-sha256"],"explicit publication plan SHA"):return false
	var plan:=read_dict(options.plan)
	if not check(plan.get("items") is Array and plan.items.size()==2,"exactly two S12 replacement plans"):return false
	guards[options.plan]=options["plan-sha256"]
	if options.has("resume-receipt"):
		var prior:=read_dict(options["resume-receipt"])
		if not check(prior.get("plan_sha256")==options["plan-sha256"] and prior.get("plan_path")==options.plan and prior.get("ok")==false and prior.get("completed")==false and prior.get("staged") is Dictionary,"explicit resume binds the same failed plan"):return false
		resume_staged=prior.staged
		guards[options["resume-receipt"]]=FileAccess.get_sha256(options["resume-receipt"])
		audit.resume_receipt={"path":options["resume-receipt"],"sha256":guards[options["resume-receipt"]]}
	var raw:=raw_catalog(folder)
	if not check(raw.get("ok",false),"catalog raw array/entry types and relative disk paths: "+str(raw.get("error","valid"))):return false
	var library:=Library.new(folder)
	if not check(library._revision==raw.sha256 and library.entries.size()==raw.entries.size(),"normal library retains every validated raw entry"):return false
	audit.catalog_entries_before=library.entries.duplicate(true);audit.catalog_sha_before=library._revision
	var seen:Dictionary={};var targets:Dictionary={}
	for data:Variant in plan.items:
		if not check(data is Dictionary and data.has_all(["id","old_asset_path","expected_old_entry","source_path","source_sha256","review_path","review_sha256"]),"complete typed S12 plan item"):return false
		var row:Dictionary=data.duplicate(true)
		if not check(row.id is String and LEGACY.has(row.id) and not seen.has(row.id) and row.expected_old_entry is Dictionary,"unique permitted S12 identity"):return false
		seen[row.id]=true
		for key:String in ["old_asset_path","source_path","review_path"]:
			if not check(row[key] is String and str(row[key]).is_absolute_path(),"explicit absolute "+key):return false
			row[key]=canonical(row[key])
		if not check(row.old_asset_path==folder.path_join(LEGACY[row.id].file),"exact permitted old immutable asset "+row.id):return false
		var old_raw:Array=raw.entries.filter(func(entry):return entry.get("asset_path")==LEGACY[row.id].file)
		if not check(old_raw.size()==1 and same_entry(old_raw[0],row.expected_old_entry),"old raw entry matches accepted snapshot "+row.id):return false
		row.old_entry=resolve_entry(row.expected_old_entry,folder)
		if not check(row.old_entry.get("label")==LEGACY[row.id].label and row.old_entry.get("category")=="街景建筑" and library.entries.filter(func(entry):return entry.get("label")==row.old_entry.label).size()==1,"original formal label/category are unique and retained "+row.id):return false
		if not check(Paths.allowed(row.source_path) and str(row.source_path).get_extension()=="glb" and Compile._sha(row.source_sha256) and FileAccess.get_sha256(row.source_path)==row.source_sha256,"accepted candidate source SHA "+row.id):return false
		row.target=folder.path_join(row.source_sha256+".glb")
		if not check(row.target!=row.old_asset_path and not targets.has(row.target) and not LEGACY.values().any(func(value):return value.label==str(row.source_path).get_file().get_basename()),"distinct revision and nonambiguous staging name "+row.id):return false
		targets[row.target]=true
		if not check(Compile._sha(row.review_sha256) and FileAccess.get_sha256(row.review_path)==row.review_sha256,"acceptance report SHA "+row.id):return false
		var proof:=read_dict(row.review_path);var identity:Dictionary=proof.get("identity",{}) if proof.get("identity") is Dictionary else {}
		if not check(proof.get("passed",false) and canonical(str(proof.get("source_path",identity.get("path",""))))==row.source_path and str(proof.get("source_sha256",identity.get("sha256","")))==row.source_sha256,"passed proof binds exact candidate "+row.id):return false
		var gpu:Dictionary=proof.get("gpu_report",{})
		if not check(gpu.get("path") is String and Compile._sha(gpu.get("sha256")) and FileAccess.get_sha256(gpu.path)==gpu.sha256,"accepted GPU report link remains exact "+row.id):return false
		var gpu_report:=read_dict(gpu.path)
		if not check(gpu_report.get("passed",false) and gpu_report.get("generator")==Compile.generator() and gpu_report.get("identity",{}).get("sha256")==row.source_sha256 and gpu_report.get("actual_materials") is Array,"accepted runtime material evidence matches current generator "+row.id):return false
		row.expected_materials=gpu_report.actual_materials;row.gpu_report=gpu
		guards[gpu.path]=gpu.sha256
		if not check(Embedded.can_copy(row.source_path),"candidate can be imported byte-identically "+row.id):return false
		var existing:=matches_path(library.entries,row.target)
		if not existing.is_empty():
			var resumed:Dictionary=resume_staged.get(row.id,{})
			if not check(existing.size()==1 and resumed.get("entry") is Dictionary and same_entry(existing[0],resumed.entry) and resumed.entry.get("asset_path")==row.target and resumed.entry.get("label")==str(row.source_path).get_file().get_basename() and resumed.entry.get("category")=="导入模型","only exact receipt-owned staged entry can resume "+row.id):return false
		if FileAccess.file_exists(row.target) and not check(FileAccess.get_sha256(row.target)==row.source_sha256,"existing new content-addressed bytes intact "+row.id):return false
		var old_sha:String=str(LEGACY[row.id].file).get_basename()
		if not check(FileAccess.get_sha256(row.old_asset_path)==old_sha,"old source bytes remain intact "+row.id):return false
		guards[row.old_asset_path]=old_sha;guards[row.source_path]=row.source_sha256;guards[row.review_path]=row.review_sha256
		if FileAccess.file_exists(row.old_entry.thumbnail_path):guards[row.old_entry.thumbnail_path]=FileAccess.get_sha256(row.old_entry.thumbnail_path)
		replacements.append(row)
	return true

func commit_replacements(folder:String)->bool:
	for attempt in 3:
		var raw:=raw_catalog(folder)
		if not check(raw.get("ok",false),"fresh commit raw catalog is losslessly supported"):return false
		var library:=Library.new(folder)
		if library._revision!=raw.sha256:await process_frame;continue
		var before:=library.entries.duplicate(true)
		var transaction:=replacement_snapshot(before,replacements,audit.staged)
		if not check(transaction.get("ok",false),"scoped two-entry replacement: "+str(transaction.get("error","valid"))):return false
		audit.commit_intent={"revision":library._revision,"items":transaction.items,"entry_count":transaction.entries.size()}
		if not flush():return false
		library.entries=transaction.entries
		var error:=library.save()
		if error==ERR_BUSY:audit.get_or_add("catalog_revision_retries",[]).append(attempt+1);await process_frame;continue
		if not check(error==OK,"revision-checked atomic two-entry catalog replacement"):return false
		audit.catalog_replaced=true;audit.items=transaction.items
		var fresh:=Library.new(folder)
		for expected_entry:Dictionary in transaction.entries:
			if not check(contains_entry(fresh.entries,expected_entry),"transaction entry retained "+str(expected_entry.label)):return false
		for row:Dictionary in replacements:
			if not check(matches_path(fresh.entries,row.old_asset_path).is_empty() and matches_path(fresh.entries,row.target).size()==1 and fresh.entries.filter(func(entry):return entry.get("label")==row.old_entry.label).size()==1,"one unambiguous current formal label "+row.id):return false
		var final_raw:=raw_catalog(folder)
		if not check(final_raw.get("ok",false),"published raw JSON keeps relative typed paths"):return false
		var modified_paths:Array=[]
		for row:Dictionary in replacements:modified_paths.append(row.old_asset_path);modified_paths.append(row.target)
		for unchanged:Dictionary in raw.entries:
			if canonical(folder.path_join(str(unchanged.get("asset_path","")))) in modified_paths:continue
			if not check(contains_entry(final_raw.entries,unchanged),"unrelated raw disk entry unchanged "+str(unchanged.label)):return false
		for item:Dictionary in audit.items:
			var staged:Dictionary=audit.staged[item.id]
			item.native_identity=staged.native_identity;item.compiled_asset=staged.compiled_asset
			item.material_proof=staged.material_proof
			item.thumbnail_path=staged.entry.thumbnail_path;item.thumbnail_sha256=FileAccess.get_sha256(item.thumbnail_path)
		audit.catalog_count_after=fresh.entries.size();audit.formal_library_modified=true
		return true
	return check(false,"catalog stayed busy; no stale replacement written")

func finish()->void:
	for path:String in guards:check(FileAccess.get_sha256(path)==guards[path],"protected old/new source, proof, plan or map unchanged "+path.get_file())
	if audit.has("catalog_path"):
		audit.catalog_sha_after=FileAccess.get_sha256(audit.catalog_path)
		if audit.has("catalog_sha_before"):audit.formal_library_modified=audit.catalog_sha_after!=audit.catalog_sha_before
	audit.completed=audit.failures.is_empty() and audit.items.size()==2 and audit.get("catalog_replaced",false)
	audit.ok=audit.completed
	var persisted:=flush()
	print("S12_STONE_IMPORT completed=",audit.completed," receipt_persisted=",persisted)
	quit(0 if audit.completed and persisted else 1)

func run()->void:
	if "--syntax-only" in OS.get_cmdline_user_args():print("S12_STONE_IMPORT syntax only");quit();return
	if OS.get_cmdline_user_args()==PackedStringArray(["--guard-self-test"]):entry_guard_self_test();return
	if not parse_options():quit(2);return
	if not check(options.get("publish",false) and DisplayServer.get_name()!="headless","explicit publication on private GPU desktop"):finish();return
	Engine.max_fps=60;root.size=Vector2i(420,320)
	var folder:=Paths.external_root().path_join("packs/default/assets")
	audit.merge({"plan_path":options.plan,"plan_sha256":options["plan-sha256"],"catalog_path":folder.path_join("library.json"),"staged":{},"catalog_replaced":false,"scope":"Two existing S12 formal labels updated; old immutable assets retained. No map edits. External file import uses the UI AssetLibrary API; MCP has no generic external-GLB import endpoint.","generator":Compile.generator()})
	if not check(Packs.new().packs().any(func(pack):return canonical(pack.root)==folder.get_base_dir() and pack.shared),"normal shared default resource pack registered"):finish();return
	if not prepare_plan(folder):finish();return
	var map_path:=Paths.external_root().path_join("maps/medieval_river_town/map.gltf")
	if FileAccess.file_exists(map_path):guards[map_path]=FileAccess.get_sha256(map_path)
	if not flush():quit(1);return
	for row:Dictionary in replacements:
		# Recheck the current target immediately before normal import. An unrelated
		# preexisting entry is never adopted merely because its SHA filename fits.
		var library:=Library.new(folder);var existing:=matches_path(library.entries,row.target)
		if not existing.is_empty() and not check(resume_staged.has(row.id) and existing.size()==1 and same_entry(existing[0],resume_staged[row.id].entry),"staged import ownership still current "+row.id):finish();return
		var imported:=library.import_file(row.source_path)
		audit.staged[row.id]=imported
		if not flush():quit(1);return
		if not check(imported.get("ok",false) and imported.get("entry") is Dictionary,"normal UI importer succeeded "+row.id):finish();return
		if not check(imported.entry.get("asset_path")==row.target and FileAccess.get_sha256(row.target)==row.source_sha256,"published candidate is byte-identical "+row.id):finish();return
		if not check(imported.get("compiled_asset",{}).get("ok",false) and imported.get("compiled_asset",{}).get("footprint",{}).get("ok",false),"real native and production footprint ready "+row.id):finish();return
		var native:=Library._verified_compiled_identity(row.target)
		if not check(not native.is_empty() and native.get("source_sha")==row.source_sha256,"verified current source/native identity "+row.id):finish();return
		var product:=Compile.read(row.target);var hit:bool=product.get("hit",false)
		if not check(hit,"closed native product reopens "+row.id):Drainer.dispose_result(product);finish();return
		var native_scene:Node=Compile.instantiate(product.packed)
		if not check(native_scene!=null,"production native scene instantiates for actual material proof "+row.id):Drainer.dispose_result(product);finish();return
		root.add_child(native_scene)
		for frame in 3:await process_frame
		var actual:=actual_material_snapshot(native_scene,row.id)
		audit.staged[row.id].material_proof={"generator":Compile.generator(),"candidate_gpu_report":row.gpu_report,"actual_materials":actual.actual_materials,"actual_valid":actual.ok,"matches_accepted_candidate":actual.ok and same_material_evidence(actual.actual_materials,row.expected_materials),"scope":"Production closed native instantiated; actual get_active_material and RGBA8 base-level texture pixels compared with accepted GPU report. Metallic, roughness and normal_scale compare exact native float32 bits; integer counts/enums compare exact numeric values with JSON floats; all strings, booleans and channel SHA exact. No epsilon."}
		native_scene.queue_free();await process_frame;Drainer.dispose_result(product)
		if not check(audit.staged[row.id].material_proof.matches_accepted_candidate,"formal native actual material parameters, tangents and channel pixels match accepted candidate "+row.id):finish();return
		if not check(await make_thumbnail(imported.entry),"production thumbnail ready "+row.id):finish();return
		if thumbs!=null:thumbs.queue_free();thumbs=null;await process_frame
		audit.staged[row.id].native_identity=native
		if not flush():quit(1);return
	if not await commit_replacements(folder):finish();return
	finish()
