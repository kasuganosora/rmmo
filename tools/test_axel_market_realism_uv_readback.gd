extends "res://tools/review_axel_market_realism_20261016.gd"
## Headless real-import UV pairing probe, not GPU or visual acceptance.
func run()->void:
	var input:=ROOT.path_join("pipeline/uv_contract_baseline_source.json")
	var expected:=read_json(input);var filename:String=expected.source
	if FileAccess.get_sha256(filename)!=expected.source_sha256:push_error("Source SHA mismatch");quit(1);return
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	if document.append_from_file(filename,state)!=OK:push_error("Real import failed");quit(1);return
	var scene:=Io.generate_scene(document,state);var nodes:Array=[];gather(scene,nodes)
	var actual:Dictionary={};var failures:Array=[];var negatives:Array=[]
	var expected_materials:Dictionary={}
	for material:Dictionary in expected.materials:expected_materials[material.name]=material
	for node:Node in nodes:
		if not node is MeshInstance3D or node.mesh==null:continue
		for slot in node.mesh.get_surface_count():
			var mat:Material=node.get_active_material(slot)
			if not actual.has(mat.resource_name):actual[mat.resource_name]=[]
			var arrays:Array=node.mesh.surface_get_arrays(slot)
			var proof:=bound_uv_sampling(arrays,expected_materials[mat.resource_name].primitive_uv_sampling)
			var altered:Array=arrays.duplicate(true);var wrong_uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV].duplicate();wrong_uv[0]+=Vector2(.02,.03);altered[Mesh.ARRAY_TEX_UV]=wrong_uv
			var wrong:=bound_uv_sampling(altered,expected_materials[mat.resource_name].primitive_uv_sampling)
			negatives.append({"material":mat.resource_name,"changed_source_uv_pair_rejected":not wrong.get("passed",false)})
			if wrong.get("passed",false):failures.append(mat.resource_name+" changed UV wrongly accepted")
			proof.first_positions=var_to_str(arrays[Mesh.ARRAY_VERTEX].slice(0,6));proof.first_uv=var_to_str(arrays[Mesh.ARRAY_TEX_UV].slice(0,6))
			proof.first_indices=var_to_str(arrays[Mesh.ARRAY_INDEX].slice(0,12)) if arrays[Mesh.ARRAY_INDEX]!=null else "none"
			actual[mat.resource_name].append(proof)
	for material:Dictionary in expected.materials:
		if material.channels.is_empty():continue
		var hashes:Array=[]
		for row:Dictionary in actual.get(material.name,[]):hashes.append(row.get("source_corner_sha256","invalid") if row.get("passed",false) else "invalid")
		var wanted:Array=[]
		for row:Dictionary in material.primitive_uv_sampling:wanted.append(row.position_uv_corner_sha256)
		hashes.sort();wanted.sort()
		if hashes!=wanted:failures.append(material.name)
	var output:=ROOT.path_join("pipeline/uv_contract_baseline_readback.json")
	put(output,{"passed":failures.is_empty(),"source":filename,"source_sha256":expected.source_sha256,"source_proof_path":input,"source_proof_sha256":FileAccess.get_sha256(input),"actual_uv_pairing":actual,"negative_uv_tests":negatives,"failed_materials":failures,"scope":"Actual source GLB through production GLTF postprocessing in headless mode; source position/UV vertex pairing and triangle vertex sets retained within explicit renderer compression precision. No GPU/visual or formal publication claim.","history":"Initial exact float32 hash-only probe failed because renderer quantizes ordinary POSITION and UV values; exact source hash remains a diagnostic, bounded numeric comparison is the actual gate.","review_script_sha256":FileAccess.get_sha256("res://tools/review_axel_market_realism_20261016.gd")})
	scene.free();print("MARKET_UV_SOURCE_READBACK ",JSON.stringify({"passed":failures.is_empty(),"failed_materials":failures,"report":output}));quit(0 if failures.is_empty() else 1)
