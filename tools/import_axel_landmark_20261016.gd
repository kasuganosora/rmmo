extends "res://tools/import_s2_green_post.gd"
## Reuse the normal immutable AssetLibrary publisher; no map writes.
## Acceptance JSON must bind the final source, image review and actual HTTP run.
const Imported=preload("res://scripts/world3d/imported_building.gd")

func same_entry(actual:Dictionary,expected:Dictionary)->bool:
	if actual.has("model_building")!=expected.has("model_building"):return false
	if actual.has("model_building") and not Imported.same(actual.model_building,expected.model_building):return false
	var left:=actual.duplicate();var right:=expected.duplicate()
	left.erase("model_building");right.erase("model_building")
	return super.same_entry(left,right)

func parse_options()->bool:
	if not super.parse_options():return false
	var proof:=read_dict(options.review)
	if not check(proof.get("resource_status")=="passed" and proof.get("visual_status")=="passed" and proof.get("pipeline_status")=="passed","final source has separate resource, visual and real pipeline acceptance"):return false
	for evidence:Dictionary in proof.get("evidence",[]):
		if not check(FileAccess.file_exists(evidence.path) and FileAccess.get_sha256(evidence.path)==evidence.sha256,"acceptance evidence bytes "+str(evidence.path).get_file()):return false
		guards[evidence.path]=evidence.sha256
	if not check(proof.get("evidence",[]).size()>=3,"CPU, GPU and HTTP evidence supplied"):return false
	var path:=canonical(Paths.external_root().path_join("packs/default/maps/axel_town/map.gltf"))
	# The separate layout owner is actively saving this map. Observe it without
	# treating that owner's concurrent save as a failure of a catalog-only tool.
	if FileAccess.file_exists(path):audit.axel_map_observation={"path":path,"before_sha256":FileAccess.get_sha256(path),"publisher_write_operations":0}
	return true

func finish()->void:
	if audit.has("axel_map_observation"):
		var observation:Dictionary=audit.axel_map_observation
		observation.after_sha256=FileAccess.get_sha256(observation.path)
		observation.changed_during_run=observation.before_sha256!=observation.after_sha256
		observation.note="Layout task owns map writes. This publisher only imports and saves catalog resources."
	super.finish()
