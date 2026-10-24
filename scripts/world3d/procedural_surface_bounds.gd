extends RefCounted
## Immutable procedural arrays are scanned by their existing preparation worker.
## The main-thread resource receives the exact result without a second scan.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
static var enabled:=true
static func bounds(surfaces:Array)->AABB:
	var first:=true;var result:=AABB()
	for surface:Array in surfaces:
		for point:Vector3 in surface[Mesh.ARRAY_VERTEX]:
			result=AABB(point,Vector3.ZERO) if first else result.expand(point)
			first=false
	return result
static func make_cpu(surfaces:Array,materials:Array,box:AABB)->Mesh:
	var result:=Cpu.new();result.surfaces=surfaces;result.materials.assign(materials);result.bounds=box
	return result
