extends RefCounted
## One-shot native buffer packing by the procedural worker. No renderer RID,
## material or Mesh is created until the main-thread consumer installs it.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const META:=&"prepared_cpu_upload"
const MAX_BYTES:=16*1024*1024
static var enabled:=true
static var installed_surfaces:=0
static var profile_enabled:=false
static var profile_rows:Array=[]

class Payload extends RefCounted:
	var surfaces:Array=[]
	var bytes:=0
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE and bytes>=8*1024*1024 and Thread.is_main_thread() and Engine.get_main_loop()!=null:
			# The packet can also be held by a material projection or a test caller.
			# Retirement owns its outer array and never clears a borrowed container.
			preload("res://scripts/world3d/resource_retirement.gd").defer_cpu_values(surfaces.duplicate(),bytes)

static func prepare(surfaces:Array,byte_limit:int,surface_lods:Array=[])->Payload:
	if not enabled or not RenderingServer.has_method(&"mesh_prepare_surface_from_arrays"):return null
	# Roads already reserve two output buffers plus the mesher workspace. The
	# caller lends only the second output allowance; never increase admission.
	if surfaces.is_empty() or byte_limit<=0 or byte_limit>MAX_BYTES:return null
	var packet:=Payload.new()
	for slot:int in surfaces.size():
		var packed:Dictionary=RenderingServer.call(&"mesh_prepare_surface_from_arrays",Mesh.PRIMITIVE_TRIANGLES,surfaces[slot],[],surface_lods[slot] if slot<surface_lods.size() else {},0)
		if packed.is_empty():return null
		for field:String in ["vertex_data","attribute_data","skin_data","index_data"]:packet.bytes+=packed.get(field,PackedByteArray()).size()
		# ArrayMesh's serialized LOD array alternates distance and index bytes.
		# RenderingServer.mesh_get_surface uses a different dictionary layout.
		var levels:Array=packed.get("lods",[])
		for at:int in range(1,levels.size(),2):packet.bytes+=levels[at].size()
		if packet.bytes>byte_limit:return null
		packet.surfaces.append(packed)
	return packet

static func attach(cpu:Mesh,packet:Payload)->void:
	if packet==null:return
	assert(cpu is Cpu and cpu.source_reference==null and packet.surfaces.size()==cpu.surfaces.size())
	cpu.set_meta(META,packet)

static func inherit(source:Mesh,target:Mesh)->void:
	if source.has_meta(META):target.set_meta(META,source.get_meta(META))

static func restore(cpu:Mesh,label:String="")->Mesh:
	assert(Thread.is_main_thread())
	# Original source generations and all later editor changes continue through
	# Cpu.restore's existing invalidation/material compatibility checks.
	if not enabled or not cpu.has_meta(META) or cpu.source_reference!=null:
		var started:=Time.get_ticks_usec() if profile_enabled else 0
		var result:Mesh=cpu.restore()
		if profile_enabled and Time.get_ticks_usec()-started>=1000:
			var elapsed:=Time.get_ticks_usec()-started
			var counts:Array=[]
			for surface:Array in cpu.surfaces:counts.append(surface[Mesh.ARRAY_VERTEX].size())
			profile_rows.append({"uuid":label,"elapsed_us":elapsed,"vertices":counts,"frame":Engine.get_process_frames(),"bounds":str(cpu.bounds)})
		return result
	var packet:Payload=cpu.get_meta(META)
	var installed:Array=[]
	for slot:int in packet.surfaces.size():
		var surface:Dictionary=packet.surfaces[slot].duplicate()
		surface.material=cpu.materials[slot];installed.append(surface)
	var result:=ArrayMesh.new();result.set("_surfaces",installed)
	var cached:Mesh=Cpu.remember(result,cpu.surfaces,cpu.lods)
	cpu.source_reference=cached.source_reference;cached._collision_faces=cpu._collision_faces
	if cpu.has_meta("static_batch_geometry_signature"):cached.set_geometry_key(cpu.geometry_key())
	installed_surfaces+=packet.surfaces.size()
	cpu.remove_meta(META)
	return result
