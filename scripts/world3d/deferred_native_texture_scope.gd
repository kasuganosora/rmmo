extends RefCounted
## A scalar metadata pin shared by pre-dispatch, the job and detached drainer.
## No Nodes, materials or textures are hidden in this cleanup edge.
var catalog:RefCounted
var candidate:Dictionary
var root:String
var consumer:String
var released:=false
var prepared:Dictionary={}
var _prefab_plan:Dictionary={}
var _merged_plan:Dictionary={}
var _merged_sources:Dictionary={}
func merge_plan(prefab:Dictionary,native:Dictionary)->Dictionary:
	if prefab.get("rows",{}).is_empty():
		_prefab_plan={};_merged_plan={};_merged_sources={};return native
	if is_same(prefab,_prefab_plan):return _merged_plan
	var rows:Dictionary=prefab.rows.duplicate();rows.merge(native.rows)
	_prefab_plan=prefab
	_merged_plan=preload("res://scripts/world3d/prefab_texture_preparation.gd")._plan_from_rows(rows)
	_merged_sources={}
	for key:String in rows:_merged_sources[key]=[rows[key].path,rows[key].flip,rows[key].normal]
	return _merged_plan
func sources(native:Dictionary)->Dictionary:
	return native.sources if _merged_plan.is_empty() else _merged_sources
func release_now()->void:
	if released:return
	assert(Thread.is_main_thread());released=true
	_prefab_plan={};_merged_plan={};_merged_sources={};prepared={}
	if catalog!=null:catalog.release_model(candidate,root,consumer)
	catalog=null;candidate={}
