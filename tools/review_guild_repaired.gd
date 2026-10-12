extends "res://tools/review_guild_full_building.gd"
const Components=preload("res://scripts/world3d/model_components.gd")
var batcher:Node3D
func prepare_review_state(state:GLTFState)->void:
	if case_name=="candidate":report.lod_derivation=preload("res://scripts/world3d/model_lod_preparation.gd").prepare(state)
func prepare_render_scene(scene:Node,viewport:SubViewport,_camera:Camera3D)->void:
	# Normal WorldDocument adapter, shared with both UI and gameplay import.
	var doc:=preload("res://scripts/world3d/world_document.gd").new()
	doc._namespace_asset(scene,"guild_review",scene)
	Components.apply(scene,{"kind":"asset","uuid":"guild_review"})
	if case_name!="candidate":return
	batcher=preload("res://scripts/world3d/ground_batcher.gd").new();viewport.add_child(batcher)
	var meshes:=preload("res://scripts/world3d/surface_materials.gd").meshes(scene)
	batcher.sync(meshes);batcher.flush()
	report.batching={"groups":batcher.groups.size(),"source_meshes":meshes.size(),"rebuilds":batcher.rebuild_count,"max_build_ms":batcher.max_build_ms,"scope":"Existing production batcher with separate semantic groups and hinge IDs; original sources retained."}
