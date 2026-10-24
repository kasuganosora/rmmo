extends SceneTree
## Reproduce creation/serialization of materials hidden by the white override.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func trial(records:Array,arrays:Array,reuse:bool)->Dictionary:
	Doc.white_entry_material_reuse_enabled=reuse
	var doc:=Doc.new();doc.load_immutable_records=true;doc.load_box_meshes={};doc.load_paint_validation={};doc.load_texture_checks={};doc.load_material_pool={}
	var specs:Array=[];var mesh_us:=0;var active:Array=[];var unique:Dictionary={}
	for record:Dictionary in records:
		var input:Dictionary=record
		doc.load_surface_arrays[input.uuid]=arrays
		var began:=Time.get_ticks_usec();var visual:MeshInstance3D=doc._mesh(input)
		mesh_us+=Time.get_ticks_usec()-began
		for material:Material in visual.mesh.materials:
			if material!=null:unique[material.get_instance_id()]=true
		var spec:=Stream._spec(visual);specs.append(spec);visual.free()
		# This is the actual later publication transformation. Effective white
		# geometry/materials must match, regardless of discarded fallback color.
		var comparison:Dictionary=spec.duplicate();Controls.whiten_spec(comparison)
		active.append([comparison.uuid,comparison.transform,comparison.mesh.surfaces,comparison.mesh.bounds,comparison.mesh.materials,comparison.extras])
	var began:=Time.get_ticks_usec();var packed:=Cook.pack(doc.load_box_meshes,"source","generator",specs);var pack_us:=Time.get_ticks_usec()-began
	check(Cook.valid_data(packed),"cooked data has valid geometry and material contracts")
	var reopened:Dictionary=bytes_to_var(var_to_bytes(packed))
	Cook.restore(reopened)
	var restored:Array=Cook.restore_specs(reopened,records)
	check(restored.size()==records.size(),"cold build reopens all selected record slots")
	var fallback:=0;var reopened_active:Array=[]
	for spec:Dictionary in restored:
		if spec.is_empty():fallback+=1;continue
		Controls.whiten_spec(spec)
		reopened_active.append([spec.uuid,spec.transform,spec.mesh.surfaces,spec.mesh.bounds,spec.mesh.materials,spec.extras])
	check((fallback==0 and reopened_active==active) if reuse else fallback==records.size(),"warm cache reuses exact white specs; legacy override reproduces fallback")
	return {"mesh_us":mesh_us,"pack_us":pack_us,"materials":unique.size(),"serialized_materials":packed.materials.size(),"fallback_specs":fallback,"active":active}

func guards(arrays:Array)->void:
	Doc.white_entry_material_reuse_enabled=true
	var doc:=Doc.new();doc.load_immutable_records=true;doc.load_box_meshes={}
	var water:Dictionary={"uuid":"water","kind":"box","surface_id":"water","color":[.2,.3,.4],"position":[0.,0.,0.],"size":[4.,1.,4.],"water_depth_effect":{},"channel_mesh":{"path":[[0.,0.,0.],[4.,0.,0.]],"width":2.,"depth":1.}}
	doc.load_surface_arrays.water=[arrays[0],arrays[0],arrays[0],arrays[0]]
	var white:Material=Controls.white_material();var original:=Cook.material_data(white)
	var visual:MeshInstance3D=doc._mesh(water)
	check(visual.mesh is Cpu and visual.mesh.materials==[white,white,white,white] and visual.material_override==null,"white water and kerb slots share canonical material without overrides")
	check(Cook.material_data(white)==original,"water cannot mutate the shared white roughness or metallic values")
	visual.free()
	# An editable or ordinary document must still reconstruct authored color.
	Controls.white_materials=false;Controls.discard_map_textures=false
	var record:Dictionary={"uuid":"ordinary","kind":"box","surface_id":"ground","color":[.2,.3,.4],"position":[0.,0.,0.],"size":[4.,1.,4.],"terrain_mesh":{}}
	doc.load_surface_arrays.ordinary=arrays
	visual=doc._mesh(record)
	check(visual.mesh.materials[0]!=white and visual.mesh.materials[0].albedo_color==Color(.2,.3,.4),"ordinary CPU entry preserves authored color")
	visual.free()
func run()->void:
	Controls.enable_white_materials();Controls.discard_map_textures=true
	var records:Array=[]
	for i:int in 322:
		records.append({"uuid":"tile%d"%i,"kind":"box","surface_id":"ground","collision":"walk","color":[.3,.4,.5],"position":[float(i),0,0],"rotation":[0,0,0],"size":[4.,1.,4.],"terrain_mesh":{"version":1,"columns":2,"rows":2,"floor":-2.,"heights":[0.,0.,0.,0.,0.,0.,0.,0.,0.],"holes":[false,false,false,false]}})
	var surface:Array=[];surface.resize(Mesh.ARRAY_MAX);surface[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK]);var arrays:Array=[surface]
	var before:=var_to_bytes(records);var expected:Array=[];var trials:Array=[]
	for simplified:bool in [false,true,true,false]:
		var row:=trial(records,arrays,simplified)
		if expected.is_empty():expected=row.active
		check(row.active==expected,"same final white channels, bounds, transforms, culling/materials and collision metadata")
		row.erase("active");row.reuse=simplified;trials.append(row)
	check(var_to_bytes(records)==before,"source authored colors and records remain untouched")
	guards(arrays)
	var report:={"trials":trials,"failures":failures}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WHITE_ENTRY_MATERIALS ",JSON.stringify(report));quit(1 if failures else 0)
