extends "res://tools/review_s10_court_tree_20261017.gd"
func run()->void:
	if DisplayServer.get_name()=="headless":quit();return
	var source_path:="D:/code/rmmo_runtime/packs/default/assets/8072add85cdbbcb157b0c372961af898fa635d9c8973543713ee1d613aaf657a.glb"
	var folder:="D:/code/rmmo_runtime/review_artifacts/s10_court_variants_20261017/planter_reuse"
	if FileAccess.file_exists(folder+"/report.json"):quit(2);return
	var sha256:=FileAccess.get_sha256(source_path)
	var doc:=GLTFDocument.new();var state:=GLTFState.new()
	if doc.append_from_file(source_path,state)!=OK:quit(2);return
	var scene:=Io.generate_scene(doc,state);doc=null;state=null
	await review_one(scene,{"id":"planter_reuse_native","path":source_path,"sha256":sha256,"source_bytes":size_of(source_path)},folder)
	check(FileAccess.get_sha256(source_path)==sha256,"original source unchanged")
	report.passed=report.failures.is_empty();put(folder+"/report.json",report);quit(0 if report.passed else 1)
