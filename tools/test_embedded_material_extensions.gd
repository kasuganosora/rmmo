extends "res://tools/test_asset_import_preparation.gd"
## Bounded headless eligibility + real staged-import regression. No GPU required.
const Bounds=preload("res://scripts/world3d/asset_bounds_manifest.gd")

func run()->void:
	var folder:=Paths.cache_directory("embedded_material_extensions_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	var f:=fixture();var source:=folder+"/source.glb"
	var library:=Library.new(folder+"/assets")
	var payloads:Dictionary={
		"KHR_materials_specular":{"specularFactor":.65,"specularColorFactor":[.6,.7,.8]},
		"KHR_materials_transmission":{"transmissionFactor":.6},
		"KHR_materials_unlit":{},
		"KHR_materials_emissive_strength":{"emissiveStrength":1.8},
		"KHR_materials_pbrSpecularGlossiness":{"diffuseFactor":[.2,.4,.6,1],"specularFactor":[.8,.7,.6],"glossinessFactor":.55},
		"KHR_materials_clearcoat":{"clearcoatFactor":.3,"clearcoatRoughnessFactor":.25},
		"KHR_materials_ior":{"ior":1.45}}
	check(payloads.size()==Bounds.MATERIAL_EXTENSIONS.size(),"tests cover the existing compiler material list without expanding it")
	for name:String in Bounds.MATERIAL_EXTENSIONS:
		var data:Dictionary=f.data.duplicate(true)
		data.extensionsUsed=[name];data.materials[0].extensions={name:payloads[name]}
		write_glb(source,data,f.binary)
		var sha:=FileAccess.get_sha256(source)
		check(Embedded.can_copy(source),"optional material is eligible "+name)
		check(Bounds.read(source).known,"existing compiler boundary accepts "+name)
		var result:Dictionary=library.import_file(source)
		check(result.get("ok",false),"staged GLTF validation still runs "+name)
		if result.get("ok",false):
			check(FileAccess.get_sha256(result.entry.asset_path)==sha,"exact input/output bytes "+name)
			check(result.import_preparation.parse_count==1 and result.import_preparation.scene_count==1,"one staged parse and scene "+name)
			check(result.import_preparation.source_sha==sha,"preparation identity bound to staged bytes "+name)
			check(not result.compiled_asset.ok and result.compiled_asset.reason=="graphics_required","headless does not impersonate GPU native acceptance "+name)
	var all_known:Dictionary=f.data.duplicate(true)
	all_known.extensionsUsed=Bounds.MATERIAL_EXTENSIONS.duplicate()
	all_known.extensionsRequired=[]
	all_known.materials[0].extensions=payloads.duplicate(true)
	write_glb(source,all_known,f.binary)
	check(Embedded.can_copy(source),"combined optional material extensions eligible")
	var bad_cases:Array=[]
	var bad:Dictionary=all_known.duplicate(true);bad.extensionsUsed=["VENDOR_unknown"];bad_cases.append(["unknown declaration",bad])
	bad=all_known.duplicate(true);bad.materials[0].extensions.VENDOR_unknown={};bad_cases.append(["unknown material payload",bad])
	bad=all_known.duplicate(true);bad.nodes[0].extensions={"KHR_materials_unlit":{}};bad_cases.append(["material name at node",bad])
	bad=all_known.duplicate(true);bad.meshes[0].primitives[0].extensions={"KHR_draco_mesh_compression":{"bufferView":0}};bad_cases.append(["geometry payload",bad])
	bad=all_known.duplicate(true);bad.extensions={"KHR_materials_unlit":{}};bad_cases.append(["root material payload",bad])
	bad=all_known.duplicate(true);bad.extras={"extensions":{"KHR_materials_unlit":{}}};bad_cases.append(["extras extension",bad])
	bad=all_known.duplicate(true);bad.materials[0].extras={"extensions":{"KHR_materials_unlit":{}}};bad_cases.append(["material extras extension",bad])
	bad=all_known.duplicate(true);bad.materials[0].extensions.KHR_materials_ior.extras={"uri":"outside.bin"};bad_cases.append(["URI inside allowed payload",bad])
	bad=all_known.duplicate(true);bad.buffers[0].uri="geometry.bin";bad_cases.append(["external buffer URI",bad])
	bad=all_known.duplicate(true);bad.extras={"nested":[{"uri":"external.png"}]};bad_cases.append(["nested extras URI",bad])
	bad=all_known.duplicate(true);bad.extensionsRequired=["KHR_materials_unlit"];bad_cases.append(["required extension stays unsupported",bad])
	bad=all_known.duplicate(true);bad.extensionsUsed="KHR_materials_unlit";bad_cases.append(["malformed declaration",bad])
	bad=all_known.duplicate(true);bad.materials[0].extensions=[];bad_cases.append(["malformed extension container",bad])
	bad=all_known.duplicate(true);bad.materials[0].extensions.KHR_materials_ior=[];bad_cases.append(["malformed extension payload",bad])
	bad=all_known.duplicate(true);bad.materials={"fake":bad.materials[0]};bad_cases.append(["nonarray material table",bad])
	bad=all_known.duplicate(true);bad.materials[0]=[];bad_cases.append(["nonobject material",bad])
	bad=all_known.duplicate(true);bad.materials[0].extensions.KHR_materials_ior.extensions={"KHR_materials_unlit":{}};bad_cases.append(["nested extension payload",bad])
	bad=all_known.duplicate(true);bad.extras={"extensionsUsed":["KHR_materials_unlit"]};bad_cases.append(["nested declaration",bad])
	for test:Array in bad_cases:
		write_glb(source,test[1],f.binary)
		check(not Embedded.can_copy(source),"packing fallback retained: "+str(test[0]))
	# Byte-copy eligibility is never a replacement for parsing the staged file.
	bad=all_known.duplicate(true);bad.meshes[0].primitives[0].attributes.POSITION=9000
	write_glb(source,bad,f.binary)
	check(Embedded.can_copy(source),"eligibility deliberately does not replace full accessor parser")
	var before:=library.entries.duplicate(true)
	var revision:=FileAccess.get_sha256(library.directory+"/library.json")
	var invalid:=library.import_file(source)
	check(not invalid.get("ok",false),"invalid staged geometry rejected by production parser")
	check(library.entries==before and FileAccess.get_sha256(library.directory+"/library.json")==revision,"staged parser failure leaves catalog unchanged")
	check(no_staging(library.directory),"staged parser failure cleans private staging")
	var current_dir:="D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2"
	for filename in ["axel_guild_repaired.glb","library/guild_hall_lantern.glb","library/guild_registration_crystal.glb","library/guild_facade_heraldry.glb","library/guild_fab_knight_statue.glb"]:
		if FileAccess.file_exists(current_dir+"/"+filename):check(Embedded.can_copy(current_dir+"/"+filename),"actual guild source eligible without mutation "+filename)
	print("EMBEDDED_MATERIAL_EXTENSIONS checks=",checks," failures=",failures," evidence=",folder)
	quit(0 if failures==0 else 1)
