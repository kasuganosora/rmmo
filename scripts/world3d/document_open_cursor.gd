extends RefCounted
## A private, main-thread validation/preparation transaction. No success flags
## from parsed JSON are trusted. Both synchronous and sliced callers drain it.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const WorldLocation=preload("res://scripts/world3d/world_location.gd")
const SourceSnapshot=preload("res://scripts/world3d/document_source_snapshot.gd")
var done:=false
var error:=""
var document:RefCounted
var metrics:Dictionary={"units":{},"max_unit_ms":0.,"max_slice_ms":0.,"slices":0,"common_records":0,"document_records":0,"record_copy_ms":0.,"max_record_copy_ms":0.}
var _path:=""
var _signature:=""
var _source:SourceSnapshot
var _data:Variant
var _mcp:=false
var _document_mode:=false
var _native:=-1
var _phase:="dependencies"
var _section:=0
var _dependency:=0
var _node:=0
var _node_ready:=false
var _node_records:Array=[]
var _record:=0
var _extras:Dictionary={}
var _raw:Variant
var _copies:Array=[]
var _meta:Dictionary={}
var _ids:Dictionary={}
var _next:=1
var _material_validation:Dictionary={}
var _metadata_step:=0
var _completed:=0
var _total:=0
var _progress:Callable

static func native_root(data: Variant) -> int:
	if not data is Dictionary:return -1
	var scenes:Variant=data.get("scenes");var nodes:Variant=data.get("nodes");var index:=int(data.get("scene",0))
	if not scenes is Array or not nodes is Array or index<0 or index>=scenes.size() or not scenes[index] is Dictionary:return -1
	var roots:Variant=scenes[index].get("nodes")
	if not roots is Array or roots.size()!=1 or not (roots[0] is float or roots[0] is int):return -1
	var root:=int(roots[0])
	if root<0 or root>=nodes.size() or not nodes[root] is Dictionary:return -1
	var node:Dictionary=nodes[root];var extra:Variant=node.get("extras")
	if not extra is Dictionary or extra.get("rmmo_format")!=WorldLocation.FORMAT or extra.get("rmmo_version")!=WorldLocation.FORMAT_VERSION or not extra.get("rmmo_records") is Array:return -1
	for field in ["translation","rotation","scale","matrix"]:
		if node.has(field):return -1
	return root

static func dependency_issue(path: String, item: Variant, require_file: bool, buffer: bool) -> String:
	if not item is Dictionary:return "Invalid glTF dependency"
	var uri:=str(item.get("uri",""))
	if uri.is_empty() or uri.begins_with("data:"):return ""
	var relative:=Io.decode_dependency_uri(uri)
	var target:=path.get_base_dir().path_join(relative)
	if relative.is_empty() or not Paths.allowed(target):return "glTF dependency is outside the allowed content root"
	if require_file:
		if not FileAccess.file_exists(target):return "Missing glTF dependency"
		if buffer:
			var file:=FileAccess.open(target,FileAccess.READ)
			if file==null or file.get_length()<int(item.get("byteLength",0)):return "Truncated glTF buffer"
	return ""

static func common_record_issue(record: Variant, material_validation: Dictionary) -> String:
	if not record is Dictionary:return "Invalid object record"
	if not Blueprint.valid_record(record):return "Invalid building component"
	if not preload("res://scripts/world3d/wind_response.gd").valid(record):return "Invalid wind response"
	if not preload("res://scripts/world3d/event_templates.gd").valid_record(record):return "Invalid 3D event template"
	if not preload("res://scripts/world3d/auto_tile_rules.gd").valid(record):return "Invalid auto tile or kit outside the allowed content root"
	if not preload("res://scripts/world3d/road_surface.gd").valid(record):return "Invalid surface material record or texture outside the allowed content root"
	if not preload("res://scripts/world3d/terrain_surface.gd").valid(record):return "Invalid terrain mesh"
	if not Paint.valid(record,false,"",material_validation):return "Invalid surface material record or texture outside the allowed content root"
	return ""

static func asset_record_issue(record: Variant, material_validation: Dictionary) -> String:
	var issue:=common_record_issue(record,material_validation)
	if not issue.is_empty():return issue
	if record.get("kind")=="asset" and not Paths.allowed(str(record.get("asset_path",""))):return "Model reference is outside the allowed content root"
	return ""

static func document_record_issue(record: Dictionary, ids: Dictionary) -> String:
	if not preload("res://scripts/world3d/channel_surface.gd").valid(record):return "Invalid channel surface"
	if not preload("res://scripts/world3d/fortification_data.gd").valid_record(record):return "Invalid fortification record"
	if not preload("res://scripts/world3d/parametric_tree.gd").valid(record):return "Invalid tree record"
	var uuid:=str(record.get("uuid",""))
	if uuid.is_empty() or ids.has(uuid):return "Invalid or duplicate object UUID"
	for field in ["position","size","rotation"]:
		var values:Variant=record.get(field)
		if not values is Array or values.size()!=3:return "Invalid object pose"
		for value in values:
			if not (value is float or value is int) or not is_finite(float(value)):return "Invalid object pose"
	ids[uuid]=true
	return ""

func begin_map_validation(path: String, data: Variant, progress: Callable=Callable()) -> void:
	_path=path;_data=data;_mcp=true;_progress=progress
	if not _data is Dictionary:_fail("Invalid glTF document")

func begin_document(path: String, prepared: Dictionary={}, mcp: bool=false, progress: Callable=Callable()) -> void:
	_path=path;_mcp=mcp;_document_mode=true;_progress=progress
	_signature=str(prepared.signature) if prepared.has("signature") else (FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "")
	_data=prepared.get("data")
	if path.get_extension().to_lower()=="gltf" and FileAccess.file_exists(path):
		if not prepared.has("data"):_data=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not _data is Dictionary:_fail("Invalid glTF document");return
		_native=native_root(_data)
		if _native>=0:_extras=_data.nodes[_native].extras;_raw=_extras.rmmo_records
	if _mcp and not _data is Dictionary:_fail("Invalid glTF document");return
	if not _mcp and _native<0:_phase="legacy"

func begin_snapshot(source: SourceSnapshot, mcp: bool=false, progress: Callable=Callable()) -> void:
	if source==null or not source.error.is_empty():
		_fail(source.error if source!=null else "Cannot read map source");return
	# Explicit internal object, not a key in prepared/JSON. The source owns the
	# path, parsed data and digest as one unit; callers cannot mix those inputs.
	begin_document(source._path,{"data":source._data,"signature":source._signature},mcp,progress)
	_source=source

func advance(budget_us: int=0) -> void:
	if done:return
	var started:=Time.get_ticks_usec()
	while not done:
		var phase_:=_phase;var unit:=Time.get_ticks_usec()
		_step()
		var elapsed:float=(Time.get_ticks_usec()-unit)/1000.
		var stats:Dictionary=metrics.units.get(phase_,{"count":0,"total_ms":0.,"max_ms":0.})
		stats.count+=1;stats.total_ms+=elapsed;stats.max_ms=maxf(stats.max_ms,elapsed);metrics.units[phase_]=stats
		metrics.max_unit_ms=maxf(metrics.max_unit_ms,elapsed)
		if budget_us>0 and Time.get_ticks_usec()-started>=budget_us:break
	metrics.slices+=1;metrics.max_slice_ms=maxf(metrics.max_slice_ms,(Time.get_ticks_usec()-started)/1000.)
	if not done and _progress.is_valid():_progress.call("validate",_completed,_total)

func _fail(message: String) -> void:
	error=message;done=true;document=null

func _step() -> void:
	match _phase:
		"dependencies":_dependency_step()
		"nodes":_node_step()
		"legacy":_legacy_step()
		"metadata":_metadata()
		"records":
			if _record>=_raw.size():_phase="ownership";return
			if _progress.is_valid():_progress.call("validate",_completed,_total)
			var record:Variant=_raw[_record]
			var issue:=common_record_issue(record,_material_validation);metrics.common_records+=1
			if not issue.is_empty():_fail(issue);return
			_append_record(record);_record+=1;_completed+=1
		"ownership":
			if not Blueprint.valid_ownership(_extras,_raw,true):_fail("Invalid building ownership");return
			_phase="metadata_copy"
		"metadata_copy":
			var meta:=_extras.duplicate();meta.erase("rmmo_records");_meta=meta.duplicate(true)
			_phase="signature"
		"signature":
			# This is the final unit: callers must publish immediately, without an
			# await after success. A large file hash is still not preemptible.
			metrics.final_check="bytes" if _source!=null and _source._retained else "sha256"
			var unchanged:bool=_source.matches_disk() if _source!=null else (_signature.length()==64 and _signature==FileAccess.get_sha256(_path))
			if not unchanged:_fail("Map changed while opening");return
			document=load("res://scripts/world3d/world_document.gd").new()
			document.records=_copies;document.map_meta=_meta;document._next=_next
			document._disk_path=ProjectSettings.globalize_path(_path).simplify_path();document._disk_signature=_signature
			done=true

func _dependency_step() -> void:
	if _section>=2:
		if _mcp:_phase="nodes"
		else:_phase="metadata";_total=_raw.size()
		return
	var section:String=["buffers","images"][_section]
	var items:Variant=_data.get(section,[])
	if not items is Array:_fail("Invalid glTF "+section);return
	if _dependency>=items.size():_section+=1;_dependency=0;return
	var issue:=dependency_issue(_path,items[_dependency],_document_mode and _native>=0,section=="buffers")
	if not issue.is_empty():_fail(issue);return
	_dependency+=1

func _node_step() -> void:
	var nodes:Variant=_data.get("nodes",[])
	if not nodes is Array:_fail("Invalid glTF nodes");return
	if _node>=nodes.size():
		if not _document_mode:done=true
		else:_phase="metadata" if _native>=0 else "legacy"
		return
	if not _node_ready:
		var node:Variant=nodes[_node]
		if not node is Dictionary or not node.get("extras",{}) is Dictionary:_fail("Invalid glTF node");return
		var records:Variant=node.get("extras",{}).get("rmmo_records",[])
		if not records is Array:_fail("Invalid glTF object records");return
		_node_records=records;_total+=records.size();_record=0;_material_validation={};_node_ready=true
		return
	if _record>=_node_records.size():_node+=1;_node_ready=false;_node_records=[];return
	if _progress.is_valid():_progress.call("validate",_completed,_total)
	var record:Variant=_node_records[_record]
	var issue:=asset_record_issue(record,_material_validation);metrics.common_records+=1
	if not issue.is_empty():_fail(issue);return
	if _document_mode and _node==_native:_append_record(record)
	_record+=1;_completed+=1

func _append_record(record: Dictionary) -> void:
	var issue:=document_record_issue(record,_ids);metrics.document_records+=1
	if not issue.is_empty():_fail(issue);return
	var uuid:=str(record.uuid)
	if uuid.begins_with("obj_"):_next=maxi(_next,int(uuid.trim_prefix("obj_"))+1)
	# Per-record copy keeps the input JSON immutable without a second town-wide
	# duplicate at publication. One very large record can exceed a frame budget.
	var started:=Time.get_ticks_usec()
	_copies.append(record.duplicate(true))
	var elapsed:float=(Time.get_ticks_usec()-started)/1000.
	metrics.record_copy_ms+=elapsed;metrics.max_record_copy_ms=maxf(metrics.max_record_copy_ms,elapsed)

func _legacy_step() -> void:
	var scene:=Io.load_scene(_path)
	if scene==null:_fail("Cannot import legacy glTF scene");return
	_extras=Io.extras_of(scene).duplicate(true);_raw=_extras.get("rmmo_records")
	if _raw==null and str(_extras.get("rmmo_format",""))==WorldLocation.FORMAT:_raw=load("res://scripts/world3d/world_document.gd")._legacy_records(scene)
	scene.free();_phase="metadata"

func _metadata() -> void:
	var valid:=true
	match _metadata_step:
		0:valid=Blueprint.valid_meta(_extras)
		1:valid=preload("res://scripts/world3d/editor_view_settings.gd").valid(_extras)
		2:valid=preload("res://scripts/world3d/city_layout.gd").valid(_extras)
		3:valid=preload("res://scripts/world3d/environment_settings.gd").valid(_extras)
		_:
			if not _raw is Array:_fail("Unsupported glTF object records");return
			if _native>=0 and _mcp:_phase="ownership"
			else:_phase="records";_record=0;_material_validation={};_total=_completed+_raw.size()
			return
	if not valid:_fail("Invalid map metadata");return
	_metadata_step+=1
