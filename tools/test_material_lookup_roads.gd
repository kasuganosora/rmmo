extends "res://tools/test_road_projection_reuse.gd"
## Reuse the full road/terrain matrix, with the same descriptor-token guard
## on both sides. Only catalog batching differs in road preparation.
const Guarded=preload("res://review_artifacts/material_lookup_20261017/road_guarded_baseline.gd")
func compare_context(name_:String,context:Node3D,args:Dictionary,current:RefCounted,_original:RefCounted,expected_ok:Variant=null,conflict:="")->Dictionary:
	var reference:=Guarded.new();reference.editor=context
	var before:=var_to_bytes([Fixture.state(context),args]);current.profile_enabled=true
	var actual:Dictionary=current.prepare(args);var expected:Dictionary=reference.prepare(args)
	record_comparison(name_,actual,expected,[Fixture.state(context),args],expected_ok,conflict)
	current.profile_enabled=false
	check(var_to_bytes(current.prepare(args))==var_to_bytes(actual) and current.last_profile.is_empty(),name_+" ON/OFF exact and disabled profile empty")
	check(before==var_to_bytes([Fixture.state(context),args]),name_+" state history authoring and arguments unchanged")
	reference.editor=null;return actual
