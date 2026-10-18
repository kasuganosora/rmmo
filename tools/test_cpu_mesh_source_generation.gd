extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func geometry(scale_:float)->Array:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT*scale_,Vector3.BACK*scale_])
	return arrays
func replace(mesh:ArrayMesh,scale_:float,material:Material)->void:
	mesh.clear_surfaces();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,geometry(scale_));mesh.surface_set_material(0,material)
func run()->void:
	var material:=StandardMaterial3D.new();var mesh:=ArrayMesh.new();replace(mesh,1.,material)
	var snapshot:Mesh=Cpu.capture(mesh)
	var projected:=Cpu.new();projected.surfaces=snapshot.surfaces.duplicate();projected.materials.assign(snapshot.materials);projected.bounds=snapshot.bounds;projected.source_reference=snapshot.source_reference
	check(snapshot.restore()==mesh,"unchanged source allocation remains reusable")
	replace(mesh,2.,material)
	var current:Mesh=Cpu.capture(mesh)
	check(current!=snapshot and current.surfaces!=snapshot.surfaces,"changed source receives a distinct current CPU owner")
	var restored:Mesh=snapshot.restore()
	check(restored!=mesh and restored.surface_get_arrays(0)==snapshot.surfaces[0],"old immutable snapshot never reuses newly recaptured geometry with the same material slots")
	var restored_projection:Mesh=projected.restore()
	check(restored_projection!=mesh and restored_projection.surface_get_arrays(0)==projected.surfaces[0],"material/CPU projections preserve the shared source generation proof")
	check(current.restore()==mesh,"recaptured current generation still reuses its exact source")
	replace(mesh,3.,material)
	var restored_second:Mesh=current.restore()
	check(restored_second!=mesh and restored_second.surface_get_arrays(0)==current.surfaces[0],"source change without recapture also invalidates the old reuse proof")
	check(current.restore()==restored_second,"restored GPU allocation is weakly shared after the source generation changes")
	var box:=BoxMesh.new();box.size=Vector3(1,2,3);box.material=material
	var original_box:Mesh=Cpu.capture(box);box.size=Vector3(4,2,3);Cpu.capture(box)
	var restored_box:Mesh=original_box.restore()
	check(restored_box is BoxMesh and restored_box!=box and restored_box.size==Vector3(1,2,3),"primitive source resize cannot replace the immutable box dimensions")
	check(original_box.restore()==restored_box,"new primitive allocation retains the same safe reuse proof")
	var mesh_watch:WeakRef=weakref(restored_second);var box_watch:WeakRef=weakref(restored_box)
	material=null;mesh=null;snapshot=null;projected=null;current=null;restored=null;restored_projection=null;restored_second=null;box=null;original_box=null;restored_box=null
	RenderingServer.force_sync();await process_frame
	check(mesh_watch.get_ref()==null and box_watch.get_ref()==null,"generation tokens keep no strong reference to original/restored GPU resources")
	print("CPU_MESH_SOURCE_GENERATION checks=",checks," failures=",failures);quit(1 if failures else 0)
