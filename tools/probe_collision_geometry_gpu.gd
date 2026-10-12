extends "res://tools/test_collision_instance_residency_gpu.gd"
## Read-only source/cache diagnostic. Never cooks, changes a source or relaxes
## promotion. Run only on the private GPU desktop; all packets drain on main.
const ResourceStore=preload("res://scripts/world3d/map_resource_store.gd")
const Descriptor=preload("res://scripts/world3d/collision_asset_descriptor.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Memory=preload("res://scripts/world3d/asset_memory_estimate.gd")

func run()->void:
	create_timer(120).timeout.connect(func():push_error("geometry probe timeout");quit(2))
	var errors:=Base.Errors.new();OS.add_logger(errors)
	var map_path:="D:/code/rmmo_runtime/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf"
	var wanted:="obj_310010";var args:=OS.get_cmdline_user_args()
	if args.size()>0:map_path=args[0]
	if args.size()>1:wanted=args[1]
	var content_root:=Paths.external_root();var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(map_path));var compact:Array=[]
	for record:Dictionary in data.nodes[0].extras.rmmo_records:
		if record.uuid==wanted:compact.append(record);break
	if not check(compact.size()==1,"requested authored record exists"):finish(errors);return
	var restored:=ResourceStore.read_records(compact,map_path,content_root,null,1)
	if not check(restored.get("ok",false),"authored reference fully validates"):print(restored);finish(errors);return
	var record:Dictionary=restored.records[0];var path:String=record.asset_path;var digest:=FileAccess.get_sha256(path)
	print("GEOMETRY_PROBE_RECORD ",JSON.stringify({"record":record,"source_sha":digest}))
	var candidate:=Descriptor.candidate(path,content_root,digest);var ledger:=Admission.new()
	# A descriptor is a bounded CPU product, not a ResourceAdmission estimate.
	# Retain its full read/workspace charge, explicitly classifying nonexclusive
	# CPU work so it can coexist with the separately charged render comparison.
	var sidecar_estimate:Dictionary={"estimated_bytes":candidate.get("estimated_bytes",0),"exclusive":false,"stage":"retained_collision_probe"}
	if not check(not candidate.is_empty() and ledger.reserve("sidecar",sidecar_estimate),"current exact source sidecar is available"):print("GEOMETRY_PROBE_ADMISSION ",JSON.stringify(ledger.inspect("sidecar",sidecar_estimate)));finish(errors);return
	var prepared:=await worker(Descriptor.read.bind(candidate,content_root,candidate.estimated_bytes));ledger.park("sidecar")
	if not check(prepared.get("ok",false),"sidecar product SHA and source SHA fully validate"):print(prepared);ledger.release("sidecar");finish(errors);return
	var geometry:Dictionary={}
	for entry:Dictionary in prepared.asset.entries():geometry[entry.node_path]=prepared.asset.geometry(entry.product)
	for mode:Dictionary in [{"label":"raw_faces","raw":true,"faces":true},{"label":"compiled_faces","raw":false,"faces":true},{"label":"core_reuse_without_faces","raw":false,"faces":false}]:
		await inspect_import(record,digest,geometry,content_root,ledger,mode)
	geometry.clear();prepared.clear();ledger.release("sidecar")
	finish(errors)

func inspect_import(record:Dictionary,digest:String,geometry:Dictionary,content_root:String,ledger:RefCounted,mode:Dictionary)->void:
	var path:String=record.asset_path;Assets.evict_cached_scene(path)
	var estimate:=Memory.estimate(path)
	if not check(ledger.reserve("import",estimate),"real import admitted: "+mode.label):print("GEOMETRY_PROBE_ADMISSION ",JSON.stringify({"estimate":estimate,"admission":ledger.inspect("import",estimate)}));return
	var prepared:=await worker(Deferred.prepare_scene.bind(path,digest,null,{},mode.faces,content_root,mode.raw));ledger.park("import")
	if not check(prepared.get("scene") is Node3D,"real import completed: "+mode.label):print(prepared);Drainer.dispose_result(prepared);ledger.release("import");return
	var before:=describe(prepared.scene,geometry)
	# Use the actual ordinary publication path: cache the prepared source,
	# instantiate through AssetLibrary, then run the full Document decorators.
	check(Assets.cache_scene(path,prepared.scene,digest),"prepared scene accepted into actual AssetLibrary: "+mode.label);prepared.erase("scene")
	var holder:=Document.new()._asset(record)
	var after:=describe(holder.get_child(0),geometry)
	var specs:Array=[];Deferred._collect_collision_asset(holder,specs)
	var collected:Array=[]
	for spec:Dictionary in specs:
		var key:String=spec.uuid.trim_prefix(str(record.uuid)+"__").replace("__","/")
		var mesh:Mesh=spec.get("collision_mesh",spec.mesh)
		var cpu:Variant=mesh if mesh is Cpu else mesh.get_meta("ground_cpu_cache",null)
		var row:Dictionary=geometry.get(key,{})
		collected.append({"uuid":spec.uuid,"mesh_class":mesh.get_class(),"mesh_script":str(mesh.get_script()),"cpu_present":cpu is Cpu,"faces":cpu._collision_faces.size() if cpu is Cpu else -1,"strict_geometry_match":Residency._geometry_matches(spec,row) if not row.is_empty() else false,"comparison":compare(cpu._collision_faces,row.get("faces",PackedVector3Array())) if cpu is Cpu else {}})
	print("GEOMETRY_PROBE_IMPORT ",JSON.stringify({"mode":mode.label,"compiled_hit":prepared.get("compiled",false),"capture_bytes":prepared.get("capture_bytes",0),"face_bytes":prepared.get("face_bytes",0),"before_library":before,"after_document_before_collect":after,"collected":collected}))
	holder.free();Assets.evict_cached_scene(path);Drainer.dispose_result(prepared);ledger.release("import")

func describe(scene:Node,geometry:Dictionary)->Array:
	var result:Array=[];var nodes:Array[Node]=[scene]
	while not nodes.is_empty():
		var node:Node=nodes.pop_back();nodes.append_array(node.get_children())
		if not node is MeshInstance3D:continue
		var mesh:Mesh=node.get_meta("collision_solid",node.get_meta("paint_source",node.mesh))
		var cpu:Variant=mesh if mesh is Cpu else mesh.get_meta("ground_cpu_cache",null)
		var path:=str(scene.get_path_to(node));var surfaces:Array=[]
		if cpu is Cpu:
			for arrays:Array in cpu.surfaces:
				var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:Variant=arrays[Mesh.ARRAY_INDEX]
				surfaces.append({"vertices":vertices.size(),"indices":indices.size() if indices!=null else 0,"vertices_sha":bytes_sha(vertices.to_byte_array()),"indices_sha":bytes_sha(indices.to_byte_array()) if indices!=null else ""})
		result.append({"node":path,"mesh_class":mesh.get_class(),"cpu_present":cpu is Cpu,"faces":cpu._collision_faces.size() if cpu is Cpu else -1,"surface_count":mesh.get_surface_count(),"surfaces":surfaces,"sidecar_faces":geometry.get(path,{}).get("faces",PackedVector3Array()).size(),"comparison":compare(cpu._collision_faces,geometry.get(path,{}).get("faces",PackedVector3Array())) if cpu is Cpu else {}})
	return result

static func bytes_sha(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty():hash.update(bytes)
	return hash.finish().hex_encode()

static func compare(actual:PackedVector3Array,expected:PackedVector3Array)->Dictionary:
	var differences:=0;var maximum:=0.;var first:Array=[]
	for i:int in mini(actual.size(),expected.size()):
		if actual[i]!=expected[i]:
			differences+=1;maximum=maxf(maximum,actual[i].distance_to(expected[i]))
			if first.size()<3:first.append({"index":i,"actual":actual[i],"expected":expected[i],"delta":actual[i]-expected[i]})
	return {"equal":actual==expected,"actual_count":actual.size(),"expected_count":expected.size(),"different_vertices":differences,"max_ordered_delta":maximum,"first":first,"actual_sha":bytes_sha(actual.to_byte_array()),"expected_sha":bytes_sha(expected.to_byte_array())}

func finish(errors:RefCounted)->void:
	OS.remove_logger(errors);check(errors.errors.is_empty(),"zero script or engine errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_GEOMETRY_PROBE checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
