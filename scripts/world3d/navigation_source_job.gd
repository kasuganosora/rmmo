extends RefCounted
## Private CPU-only source data. Never reads a scene node or render/physics RID.
var thread:Thread
var result:NavigationMeshSourceGeometryData3D
func start(chunks:Array)->void:
	thread=Thread.new()
	if thread.start(build.bind(chunks),Thread.PRIORITY_LOW)!=OK:
		thread=null;result=build(chunks)
static func build(chunks:Array)->NavigationMeshSourceGeometryData3D:
	var data:=NavigationMeshSourceGeometryData3D.new()
	for chunk:Array in chunks:data.add_faces(chunk[0],chunk[1])
	return data
func poll()->bool:
	if thread!=null:
		if thread.is_alive():return false
		result=thread.wait_to_finish();thread=null
	return true
func finish()->void:
	if thread!=null:result=thread.wait_to_finish();thread=null
