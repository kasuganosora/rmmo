extends RefCounted
## Pure CPU packing for immutable procedural meshes, before their first upload.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const META:=&"prepared_cpu_upload"
static var enabled:=true
static var installed_surfaces:=0
static func prepare(surfaces:Array)->Array:
	if not enabled or not RenderingServer.has_method(&"mesh_prepare_surface_from_arrays"):return []
	var result:Array=[]
	for surface:Array in surfaces:
		var packed:Dictionary=RenderingServer.call(&"mesh_prepare_surface_from_arrays",Mesh.PRIMITIVE_TRIANGLES,surface,[],{},0)
		if packed.is_empty():return []
		result.append(packed)
	return result
class Payload extends RefCounted:
	var surfaces:Array=[]
	var bytes:=0
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE and bytes>=8*1024*1024 and Engine.get_main_loop()!=null:
			preload("res://scripts/world3d/resource_retirement.gd").defer_cpu_values(surfaces.duplicate(),bytes)
static func attach(cpu:Mesh,packed:Array)->void:
	if packed.is_empty():return
	assert(cpu is Cpu and cpu.source_reference==null)
	var payload:=Payload.new();payload.surfaces=packed
	for surface:Dictionary in packed:
		for field:String in ["vertex_data","attribute_data","skin_data","index_data"]:
			payload.bytes+=surface.get(field,PackedByteArray()).size()
	cpu.set_meta(META,payload)
static func inherit(source:Mesh,target:Mesh)->void:
	if source.has_meta(META):target.set_meta(META,source.get_meta(META))
static func restore(cpu:Mesh)->Mesh:
	assert(Thread.is_main_thread())
	# After the first installation, the existing weak-owner generation proof,
	# material variants and editor invalidation retain the ordinary restore path.
	if not enabled or not cpu.has_meta(META) or cpu.source_reference!=null:return cpu.restore()
	var payload:Payload=cpu.get_meta(META)
	var installed:Array=[]
	for slot:int in payload.surfaces.size():
		var surface:Dictionary=payload.surfaces[slot].duplicate()
		surface.material=cpu.materials[slot];installed.append(surface)
	var result:=ArrayMesh.new();result.set("_surfaces",installed)
	var cached:Mesh=Cpu.remember(result,cpu.surfaces,cpu.lods)
	cpu.source_reference=cached.source_reference;cached._collision_faces=cpu._collision_faces
	if cpu.has_meta("static_batch_geometry_signature"):cached.set_meta("static_batch_geometry_signature",cpu.geometry_key())
	installed_surfaces+=payload.surfaces.size()
	cpu.remove_meta(META)
	return result
