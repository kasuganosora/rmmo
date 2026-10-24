extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Bounds=preload("res://scripts/world3d/procedural_surface_bounds.gd")
const Upload=preload("res://tools/prepared_cpu_upload_probe.gd")
const Fixture=preload("res://tools/test_native_road_preparation.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var f:=Fixture.new();var record:=f.road();record.road_mesh.kerbs=[]
	for i:int in 2048:record.road_mesh.kerbs.append(f.part(i%2==0,i%3==0))
	var arrays:=Road.arrays(record);var bytes:=var_to_bytes(arrays);var bounds:=Bounds.bounds(arrays)
	var materials:Array=[]
	for i:int in arrays.size():var m:=StandardMaterial3D.new();m.albedo_color=Color(.1*i,.2,.3);materials.append(m)
	var rows:Array=[]
	for prepared:bool in ([true,false,false,true] if OS.get_cmdline_user_args().has("--prepared-first") else [false,true,true,false]):
		var cpu:Mesh=Bounds.make_cpu(arrays,materials,bounds);var began:=Time.get_ticks_usec();var worker_us:=0
		if prepared:
			var thread:=Thread.new();thread.start(Upload.prepare.bind(arrays));var packed:Array=thread.wait_to_finish();worker_us=Time.get_ticks_usec()-began
			check(packed.size()==arrays.size(),"complete worker packet without mesh resources")
			Upload.attach(cpu,packed)
		began=Time.get_ticks_usec();var mesh:Mesh=Upload.restore(cpu) if prepared else cpu.restore();var install_us:=Time.get_ticks_usec()-began
		rows.append({"prepared":prepared,"main_install_us":install_us,"worker_us":worker_us})
		# Native tangent/normal packing is lossy even in the ordinary upload.
		var control:Mesh=Cpu.from_surfaces(arrays,materials).restore()
		for slot:int in arrays.size():
			check(var_to_bytes(RenderingServer.mesh_get_surface(mesh.get_rid(),slot))==var_to_bytes(RenderingServer.mesh_get_surface(control.get_rid(),slot)),"native surface bytes equal ordinary upload")
		check(mesh.get_aabb()==control.get_aabb(),"native bounds equal ordinary upload")
		check(Upload.restore(cpu)==mesh,"repeated instance reuses installed GPU resource")
		var variant:Mesh=Bounds.make_cpu(arrays,materials,bounds);variant.source_reference=cpu.source_reference;variant.materials[0]=StandardMaterial3D.new()
		var variant_mesh:Mesh=Upload.restore(variant)
		check(variant_mesh!=mesh and variant_mesh.surface_get_material(0)==variant.materials[0] and mesh.surface_get_material(0)==materials[0],"material variant stays independent")
		mesh.surface_set_material(0,StandardMaterial3D.new())
		check(Upload.restore(cpu)!=mesh,"changed original invalidates shared generation")
		check(var_to_bytes(arrays)==bytes,"borrowed geometry is unchanged")
		await process_frame
	var borrowed:Array=Upload.prepare(arrays);var borrowed_bytes:=var_to_bytes(borrowed)
	var packet:=Upload.Payload.new();packet.surfaces=borrowed;packet.bytes=16*1024*1024;packet=null
	for i:int in 12:await process_frame
	check(var_to_bytes(borrowed)==borrowed_bytes,"retired payload never mutates the borrowed outer surface array")
	f.free();var report:={"failures":failures,"runs":rows,"installed_surfaces":Upload.installed_surfaces}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):var file:=FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(1 if failures else 0)
