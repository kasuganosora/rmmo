extends RefCounted
## One build borrows READY templates. Derived pieces never enter a strong global cache.
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Kits=preload("res://scripts/world3d/auto_tile_kit.gd")
var templates:Dictionary={}
var pieces:Dictionary={}

func _init(prepared:Dictionary={})->void:
	for path:String in prepared:
		if prepared[path] is PackedScene:accept(path,prepared[path])

## Call only after the existing preparation/adoption protocol accepts READY.
## Loaders can admit later paths without rebuilding the operation's piece cache.
func accept(path:String,template:PackedScene)->void:
	var key:=_key(path)
	if templates.get(key)!=template:pieces.erase(key)
	if template==null:templates.erase(key)
	else:templates[key]=template

static func _key(path:String)->String:return path.replace("\\","/").simplify_path()

func prepared(record:Dictionary)->Dictionary:
	var owner:PackedScene=templates.get(_key(str(record.get("asset_path",""))))
	return {"template":owner} if owner!=null else {}

## Generated/painted/cooked kit meshes only. Never attach a template to one of
## its own source meshes: the native template must not point back to this mesh.
func retain(record:Dictionary,mesh:Mesh)->void:
	if mesh==null or not record.has("tile3d"):return
	var owners:Array=[];var seen:Dictionary={}
	for path:String in Kits.required_paths(record.tile3d):
		var owner:PackedScene=templates.get(_key(path))
		if owner!=null and not seen.has(owner.get_instance_id()):
			seen[owner.get_instance_id()]=true;owners.append(owner)
	if not owners.is_empty():mesh.set_meta("_compiled_resource_owners",owners)

func piece(path:String)->ArrayMesh:
	var key:=_key(path)
	if pieces.has(key):return pieces[key]
	var owner:PackedScene=templates.get(key)
	if owner==null:return null
	var instance:Node3D=Assets._instantiate(owner)
	if instance==null:return null
	var output:ArrayMesh=Kits._piece_from_scene(instance)
	instance.free()
	if output!=null:
		# Publishing a tile must keep its READY template eligible for weak reuse.
		# This owner is operation/view scoped and never serialized into records.
		output.set_meta("_compiled_resource_owners",[owner])
		pieces[key]=output
	return output
