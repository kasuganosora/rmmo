extends SceneTree
const Hint=preload("res://scripts/world3d/importer_lod_hint.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func arrays(count:int)->Array:
	var rows:Array=[];rows.resize(Mesh.ARRAY_MAX)
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var uv:=PackedVector2Array();var colors:=PackedColorArray();var tangents:=PackedFloat32Array()
	for i:int in count:
		vertices.append(Vector3(i%11,float(i%7)*.3,float(i%13)*.7));normals.append(Vector3(.1,.2,1).normalized());uv.append(Vector2(float(i%5)*.123,float(i%3)*.314));colors.append(Color(.123,.456,.789,1.));tangents.append_array(PackedFloat32Array([1.,0.,0.,1.]))
	vertices[0]=Vector3.ZERO;vertices[1]=Vector3.RIGHT;vertices[2]=Vector3.UP;vertices[count-1]=Vector3.ONE
	rows[Mesh.ARRAY_VERTEX]=vertices;rows[Mesh.ARRAY_NORMAL]=normals;rows[Mesh.ARRAY_TEX_UV]=uv;rows[Mesh.ARRAY_COLOR]=colors;rows[Mesh.ARRAY_TANGENT]=tangents;rows[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,2,1,count-1])
	return rows
func importer(count:int,with_lods:bool,compressed:bool=false)->ImporterMesh:
	var result:=ImporterMesh.new();var lods:Dictionary={2.5:PackedInt32Array([0,1,2]),8.125:PackedInt32Array([2,1,count-1])} if with_lods else {}
	result.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays(count),[],lods,StandardMaterial3D.new(),"fixture",Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES if compressed else 0)
	return result
func compare(source:ArrayMesh,label:String)->void:
	Cpu.importer_lod_hints_enabled=false
	# A separate exact ArrayMesh copy exercises the old capture path without
	# manually removing its generation cache/invalidation callback.
	var baseline:ArrayMesh=source.duplicate()
	Trace.start();var old:Mesh=Cpu.capture(baseline)
	var before:=Trace.stop();Cpu.importer_lod_hints_enabled=true
	Trace.start();var current:Mesh=Cpu.capture(source);var after:=Trace.stop()
	check(var_to_bytes(old.surfaces)==var_to_bytes(current.surfaces) and old.lods==current.lods and old.materials==current.materials and old.bounds==current.bounds,label+" preserves all GPU-decoded channels, LODs, materials and bounds")
	# Mesh.get_faces creates a TriangleMesh that snaps/welds positions. Compare
	# the previous CPU collision path, which deliberately retains decoded floats.
	check(old.collision_faces()==current.collision_faces(),label+" preserves exact previous CPU collision data")
	check(before.stats.any(func(row):return row.label=="mesh.lod_renderer_read") and not after.stats.any(func(row):return row.label=="mesh.lod_renderer_read") and after.stats.any(func(row):return row.label=="mesh.lod_importer_copy"),label+" removes the complete second renderer readback")
func run()->void:
	check(DisplayServer.get_name()!="headless","private desktop real renderer")
	for count:int in [4,70001]:
		for with_lods:bool in [false,true]:
			var owner:=importer(count,with_lods,true);var source:=Hint.create_mesh(owner)
			compare(source,"%d vertices, lods=%s"%[count,with_lods])
	var multiple:=importer(4,true,true);multiple.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays(4),[],{},StandardMaterial3D.new())
	compare(Hint.create_mesh(multiple),"multiple surfaces with mixed compression/LOD presence")
	var owner:=importer(4,true);var source:=Hint.create_mesh(owner)
	var hint:Resource=source.get_meta(Hint.META)
	var copy:Dictionary=Cpu.capture_lods(source,0);copy.clear()
	check(hint.tables[0].size()==2,"callers receive an independent LOD dictionary")
	var duplicate:ArrayMesh=source.duplicate()
	check(not duplicate.get_meta(Hint.META).matches(duplicate,0),"a duplicated mesh cannot inherit a proof for another resource")
	Trace.start();var duplicated_lods:=Cpu.capture_lods(duplicate,0);var trace:=Trace.stop()
	check(duplicated_lods==hint.tables[0] and trace.stats.any(func(row):return row.label=="mesh.lod_renderer_read"),"duplicated resource uses the exact renderer fallback")
	source.clear_surfaces();source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays(4),[],{3.:PackedInt32Array([0,2,3])})
	check(not source.has_meta(Hint.META) and hint.tables.is_empty(),"mesh mutation invalidates and releases the old CPU LOD tables")
	check(Cpu.capture_lods(source,0)=={3.:PackedInt32Array([0,2,3])},"changed geometry/LODs use current renderer data")
	var state:=GLTFState.new();var record:=GLTFMesh.new();record.mesh=importer(4,true);var node:=GLTFNode.new();node.mesh=0
	Hint.prepare(state,[node],[record]);check(record.mesh.get_mesh().has_meta(Hint.META),"static private GLTF preparation stamps the cache consumed by scene conversion")
	var untouched:=importer(4,true);record.mesh=untouched;node.skin=0;Hint.prepare(state,[node],[record])
	check(not untouched.get_mesh().has_meta(Hint.META),"skinned nodes retain the original import/capture path")
	node.skin=-1;var animation:=GLTFAnimation.new();state.animations=[animation];record.mesh=importer(4,true);Hint.prepare(state,[node],[record])
	check(not record.mesh.get_mesh().has_meta(Hint.META),"animation-bearing imports retain the original path")
	var persisted_owner:=importer(4,true);var persisted_source:=Hint.create_mesh(persisted_owner)
	var folder:String=preload("res://scripts/world3d/map_paths.gd").cache_directory("lod_hint_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("mesh.tres")
	check(ResourceSaver.save(persisted_source,path)==OK,"runtime-only hint does not prevent ordinary resource serialization")
	var loaded:ArrayMesh=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(loaded!=null and not loaded.get_meta(Hint.META).matches(loaded,0) and Cpu.capture_lods(loaded,0)==persisted_source.get_meta(Hint.META).tables[0],"reopened resources discard transient proof and preserve exact renderer LOD fallback")
	var weak_importer:WeakRef=weakref(owner);var weak_source:WeakRef=weakref(source)
	owner=null;source=null;hint=null;duplicate=null
	RenderingServer.force_sync();await process_frame
	check(weak_importer.get_ref()==null and weak_source.get_ref()==null,"hint and invalidation callback retain neither importer nor source mesh")
	print("IMPORTER_LOD_HINT checks=",checks," failures=",failures);quit(1 if failures else 0)
