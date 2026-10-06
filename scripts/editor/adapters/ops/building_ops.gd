extends RefCounted
const Generator=preload("res://scripts/editor/domain/building_generator.gd")
var _owner: WeakRef
var ctrl:
	get:return _owner.get_ref()
func _init(owner):_owner=weakref(owner)
func op_names() -> Array:return ["list_building_kits","generate_building"]
func list_building_kits(_args: Dictionary={}) -> Dictionary:
	if ctrl.doc()==null or ctrl.pack()==null:return ctrl.mcp._err("no map")
	var kits: Dictionary=ctrl.pack().tilesets.get(ctrl.doc().tileset_id,{}).get("buildingKits",{})
	return ctrl.mcp._ok({"kits":kits,"instances":ctrl.doc().building_instances})
func generate_building(args: Dictionary) -> Dictionary:
	if ctrl.doc()==null or ctrl.pack()==null:return ctrl.mcp._err("no map")
	var kits: Dictionary=ctrl.pack().tilesets.get(ctrl.doc().tileset_id,{}).get("buildingKits",{})
	var kit: Dictionary=kits.get(str(args.get("kit","")),{})
	if kit.is_empty():return ctrl.mcp._err("unknown building kit")
	var result:=Generator.place(ctrl.doc(),kit,args)
	if not result.ok:return ctrl.mcp._err(str(result.error))
	if result.has("dirty"):ctrl._touch(result.dirty);result.erase("dirty")
	return ctrl.mcp._ok(result)
func tools() -> Array:
	return [ctrl.mcp._tool("list_building_kits","List parameterized building kits and saved instances",{},[]),
	ctrl.mcp._tool("generate_building","Compose fixed-size architectural components into walls z1, details z2 and roof z3. Undoable; refuses occupied sites. Same instance_id regenerates an existing building.",{
		"kit":{"type":"string"},"x":{"type":"integer"},"y":{"type":"integer"},
		"bays":{"type":"integer","minimum":1,"maximum":3},"floors":{"type":"integer","minimum":1,"maximum":3},
		"roof":{"type":"string","enum":["red","slate"]},"windows":{"type":"boolean"},
		"instance_id":{"type":"string"},"dry_run":{"type":"boolean"}},["kit","x","y"])]
