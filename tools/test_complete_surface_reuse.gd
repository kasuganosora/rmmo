extends SceneTree
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
const Fixture=preload("res://tools/test_native_road_preparation.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func expanded(mesh:Mesh)->Array:
	var result:Array=[]
	for slot:int in mesh.get_surface_count():
		var source:Array=mesh.surface_get_arrays(slot);var count:int=source[Mesh.ARRAY_VERTEX].size()
		var indices:PackedInt32Array=source[Mesh.ARRAY_INDEX] if source[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			indices.resize(count)
			for i:int in count:indices[i]=i
		var channels:Array=[]
		for channel:int in Mesh.ARRAY_INDEX:
			var data:Variant=source[channel]
			if data==null or data.is_empty():channels.append(null);continue
			var stride:int=data.size()/count;var values:Variant=data.slice(0,0)
			for index:int in indices:
				for component:int in stride:values.append(data[index*stride+component])
			channels.append(values)
		result.append([mesh.surface_get_material(slot),channels])
	return result
func scenario(shared:bool,kerbs:int)->void:
	var fixture:=Fixture.new();var record:Dictionary=fixture.road()
	record.road_mesh.grade=[.025,-.015];record.road_mesh.kerbs=[]
	for i:int in kerbs:record.road_mesh.kerbs.append(fixture.part(i%2==0,i%3==0))
	var arrays:Array=Road.arrays(record);fixture.free()
	var material:=StandardMaterial3D.new();var slots:Array=[]
	for i:int in arrays.size():slots.append(material if shared or i<3 else StandardMaterial3D.new())
	var cpu:Mesh=Cpu.from_surfaces(arrays,slots);var node:=MeshInstance3D.new();node.set_meta("paint_source",cpu);node.set_meta("paint_source_materials",slots)
	var geo:=Paint.geometry(node,true);check(geo.ok,"road fixture topology is valid")
	var entries:Array=[]
	for face in geo.surfaces[0].faces:
		entries.append({"surface":0,"face":face,"geometry":geo.surfaces[0].signature,"mapping":"uv","scale":[.5,.25],"offset":[.125,.25],"rotation":30.,"material":{"name":"white","color":[1,1,1,1],"roughness":.9}})
	var source_bytes:=var_to_bytes(arrays);var expected:Array=[];var measurements:Array=[]
	for enabled:bool in [false,true,true,false]:
		Paint.preserve_complete_surfaces_enabled=enabled
		var began:=Time.get_ticks_usec();var result:=Paint.painted_mesh(node,entries,true,{},true);var elapsed:=Time.get_ticks_usec()-began
		check(result.ok,"geometry assembly succeeds with complete surface reuse %s"%enabled)
		if not result.ok:continue
		var canonical:=expanded(result.mesh)
		if expected.is_empty():expected=canonical
		check(canonical==expected,"exact triangle order, positions, normals, tangents, UVs and materials match control")
		check(var_to_bytes(arrays)==source_bytes,"borrowed input geometry remains byte identical")
		measurements.append({"reuse":enabled,"elapsed_us":elapsed,"surfaces":result.mesh.get_surface_count()})
	print("COMPLETE_SURFACE_REUSE ",JSON.stringify({"shared_material":shared,"kerbs":kerbs,"trials":measurements}))
	node.free()
func run()->void:
	scenario(false,512);scenario(true,512);scenario(false,2048)
	Paint.preserve_complete_surfaces_enabled=true
	print("COMPLETE_SURFACE_REUSE failures=",failures);quit(1 if failures else 0)
