extends RefCounted
## Private entry worker output. Same generators as streaming, no Mesh/Node/RID.
const Bounds=preload("res://scripts/world3d/procedural_surface_bounds.gd")
static var enabled:=true
static func prepare(record:Dictionary,context:Dictionary,build_geometry:bool,_root:String="",_definition_sha:String="",_trusted:bool=false)->Dictionary:
	var arrays:Array=[]
	if preload("res://scripts/world3d/channel_mesh_preparation.gd").supports(record):arrays=preload("res://scripts/world3d/channel_surface.gd").arrays(record)
	elif build_geometry:
		if record.has("terrain_volume"):arrays=preload("res://scripts/world3d/terrain_volume.gd").arrays(record)
		elif record.has("terrain_mesh"):arrays=preload("res://scripts/world3d/terrain_surface.gd").arrays(record,context)
		elif record.has("road_mesh"):arrays=preload("res://scripts/world3d/road_surface.gd").arrays(record)
		elif record.has("rock_bank"):arrays=preload("res://scripts/world3d/rock_bank_mesh.gd").arrays(record)
	var result:={"arrays":arrays,"road_cache_hit":false}
	if enabled and Bounds.enabled and not arrays.is_empty():result.bounds=Bounds.bounds(arrays)
	return result
