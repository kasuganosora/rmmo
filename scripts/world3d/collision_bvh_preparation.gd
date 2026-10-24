extends RefCounted
## Pure CPU native BVH products; physics RIDs are installed only by the receiver.
static var enabled:=true
const SLICE_VERTICES:=3072
static func active()->bool:
	return enabled and PhysicsServer3D.has_method(&"prepare_concave_shape_data")
static func slices(faces:PackedVector3Array)->Array:
	var result:Array=[]
	if not active():return result
	for offset:int in range(0,faces.size(),SLICE_VERTICES):
		var part:=faces.slice(offset,mini(offset+SLICE_VERTICES,faces.size()))
		result.append(PhysicsServer3D.call(&"prepare_concave_shape_data",part,false))
	return result
static func packet(faces:PackedVector3Array)->Dictionary:
	return {"faces":faces,"prepared_shapes":slices(faces)}
