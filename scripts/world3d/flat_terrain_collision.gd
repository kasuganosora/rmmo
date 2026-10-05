extends RefCounted
## Only an authored, completely solid and exactly level heightfield is a box.
## This does not approximate arbitrary imported meshes or flatten edited terrain.
static func descriptor(spec:Dictionary)->Dictionary:
	if spec.has("flat_terrain_collision"):return spec.flat_terrain_collision
	var result:Dictionary={}
	var record:Dictionary=spec.get("ground_batch_record",{})
	var terrain:Dictionary=record.get("terrain_mesh",{})
	if terrain.is_empty():return result
	spec.flat_terrain_collision=result
	var heights:Array=terrain.get("heights",[])
	var holes:Array=terrain.get("holes",[])
	var size:Array=record.get("size",[])
	if heights.is_empty() or holes.is_empty() or size.size()!=3:return result
	var columns:=int(terrain.get("columns",0));var rows:=int(terrain.get("rows",0))
	if columns<1 or rows<1 or heights.size()!=(columns+1)*(rows+1) or holes.size()!=columns*rows:return result
	var level:float=heights[0]
	var floor_:float=terrain.get("floor",level)
	if not is_finite(level) or not is_finite(floor_) or level<=floor_:return result
	if holes.any(func(h):return h) or heights.any(func(h):return float(h)!=level):return result
	if preload("res://scripts/world3d/terrain_furrows.gd").maximum_height(record)!=0.0:return result
	var extent:=Vector3(size[0],(level-floor_)*float(size[1]),size[2])
	if not extent.is_finite() or extent.x<=0 or extent.y<=0 or extent.z<=0:return result
	var shape:=BoxShape3D.new();shape.size=extent
	result={"shape":shape,"offset":Vector3(0,(level+floor_)*float(size[1])*.5,0)}
	# Stream specs are immutable geometry snapshots; an edit rebuilds the spec.
	spec.flat_terrain_collision=result
	return result
