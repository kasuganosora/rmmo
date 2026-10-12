extends "res://scripts/world_editor/picking_shape_cache.gd"
## Test-only observation: no extra face expansion, hashing or strong mesh owners.
var calls:=0
var misses:=0
var elapsed_us:=0
var missed_us:=0
var live_eviction_misses:=0
var live_eviction_us:=0
var signature_duplicates:=0
var signature_duplicate_us:=0
var faces_us:=0
var native_us:=0
var small_faces_us:=0
var expanded_meshes:=0
var expanded_vertices:=0
var seen:Dictionary={}
var geometries:Dictionary={}

func clear()->void:
	super.clear()
	calls=0;misses=0;elapsed_us=0;missed_us=0;live_eviction_misses=0;live_eviction_us=0;signature_duplicates=0;signature_duplicate_us=0
	seen.clear();geometries.clear()
	faces_us=0;native_us=0;small_faces_us=0;expanded_meshes=0;expanded_vertices=0

func shape_for(source:Mesh)->ConcavePolygonShape3D:
	var cpu:Mesh=Cpu.capture(source);var key:=cpu.get_instance_id()
	var hit:bool=_entries.has(key) and _entries[key].source.get_ref()==cpu
	var old:Dictionary=seen.get(key,{})
	var retained:bool=not hit and not old.is_empty() and old.source.get_ref()==cpu and old.shape.get_ref()!=null
	var signature:String=cpu.get_meta("static_batch_geometry_signature","")
	var shared:Dictionary=geometries.get(signature,{}) if not signature.is_empty() else {}
	var duplicate:bool=not hit and not shared.is_empty() and shared.source.get_ref()!=cpu and shared.shape.get_ref()!=null
	var before:=Time.get_ticks_usec()
	if not hit:
		var expands:bool=cpu._collision_faces.is_empty()
		var faces:PackedVector3Array=cpu.collision_faces()
		var face_time:=Time.get_ticks_usec()-before
		faces_us+=face_time
		if expands:
			expanded_meshes+=1;expanded_vertices+=faces.size()
			if faces.size()<65536:small_faces_us+=face_time
	var started:=Time.get_ticks_usec();var shape:=super.shape_for(source);var used:=Time.get_ticks_usec()-before
	if not hit:native_us+=Time.get_ticks_usec()-started
	calls+=1;elapsed_us+=used
	if not hit:misses+=1;missed_us+=used
	if retained:live_eviction_misses+=1;live_eviction_us+=used
	if duplicate:signature_duplicates+=1;signature_duplicate_us+=used
	if shape!=null:
		seen[key]={"source":weakref(cpu),"shape":weakref(shape)}
		if not signature.is_empty():geometries[signature]=seen[key]
	return shape

func snapshot()->Dictionary:
	return {"calls":calls,"misses":misses,"shape_ms":elapsed_us/1000.,"miss_ms":missed_us/1000.,"live_eviction_misses":live_eviction_misses,"live_eviction_ms":live_eviction_us/1000.,"known_signature_duplicate_misses":signature_duplicates,"known_signature_duplicate_ms":signature_duplicate_us/1000.,"observed_cpu_objects":seen.size(),"known_geometry_keys":geometries.size(),"faces_ms":faces_us/1000.,"native_shape_ms":native_us/1000.,"small_faces_ms":small_faces_us/1000.,"expanded_meshes":expanded_meshes,"expanded_vertices":expanded_vertices,"scope":"test-only weak observations; one face expansion on miss is timed before native shape creation; no geometry hashing"}
