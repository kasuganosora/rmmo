extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const House=preload("res://scripts/world3d/house_prefab.gd")
static var late_owners:Array=[]
func _initialize()->void:run.call_deferred()
func run()->void:
	var mesh:=Cpu.new();var vertices:=PackedVector3Array();vertices.resize(750000)
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
	mesh.surfaces=[arrays];late_owners.append(mesh)
	House._meshes.shutdown_fixture={"mesh":mesh};House._render_meshes.shutdown_fixture=mesh
	print("CPU_SHUTDOWN_RETIREMENT retained until script-language shutdown")
	quit(0)
