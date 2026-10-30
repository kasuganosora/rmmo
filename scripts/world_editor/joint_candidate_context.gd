extends "res://scripts/world_editor/residential_site_tools.gd".Context
## Native operations run against this detached authoring context. Presentation
## hooks are deliberately inert; no scene, physics, selection or live history.
class Presentation extends RefCounted:
	func refresh()->void:pass
class Selection extends "res://scripts/world_editor/object_selection.gd":
	func refresh(_scene:bool=true)->void:pass
	func set_ids(_values:Array)->void:pass

var _dirty:=false
var _object_list=Presentation.new()
var _selection_tools=Selection.new()
var _building_panel:Variant
var _terrain_panel:Variant
var _assets:Variant
var _shared_assets:Array=[]
var _buildings=preload("res://scripts/world_editor/building_tools.gd").new()
var _blocks=preload("res://scripts/world_editor/block_tools.gd").new()
var _bridges=preload("res://scripts/world_editor/bridge_tools.gd").new()
var _scatter=preload("res://scripts/world_editor/scatter_tools.gd").new()
var _connections=preload("res://scripts/world_editor/road_connection_tools.gd").new()
var _block_update=preload("res://scripts/world_editor/block_update_tools.gd").new()

func setup(value:Node3D)->void:
	super.setup(value)
	_city=preload("res://scripts/world_editor/city_tools.gd").new();_city.editor=self
	_assets=value._assets;_shared_assets=value._shared_assets
	for service in [_buildings,_blocks,_bridges,_scatter,_connections,_block_update]:service.editor=self
	_selection_tools.editor=self;_selection_tools.motion.editor=self;add_child(_selection_tools)
	_city.refresh()

func _commit_records(_ids:Array)->void:pass
func _refresh_records(_ids:Array,_index:Variant=null)->void:pass
func _refresh_selection(_scene:bool=true)->void:pass
func _rebuild()->Dictionary:return {"ok":true}

func _prepare_target(target:RefCounted,result:Dictionary={},_full:bool=false,_completed:Callable=Callable(),_canvas:String="",_coalesce:bool=false)->Dictionary:
	# The surrounding candidate owns this document. Presentation callbacks must
	# remain inert until the actual editor accepts the enclosing candidate.
	_doc.records=target.records;_doc.map_meta=target.map_meta;_doc._next=target._next;_dirty=true
	return result.merged({"ok":true},true)

func _replace_records(updates:Variant,removed:Variant=[],meta:Variant=null,result:Dictionary={},_completed:Callable=Callable())->Dictionary:
	return _prepare_target(preload("res://scripts/world_editor/prepared_asset_operation.gd").plan_replacements(_doc,updates,removed,meta),result)
