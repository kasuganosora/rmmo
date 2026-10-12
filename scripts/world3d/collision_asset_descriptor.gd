extends RefCounted
## Opt-in offline GLB collision directory. Geometry uses the existing .rmcp
## exact-product format; this small directory only preserves node/source mapping.
## A verified Asset is NOT map/ownership/physics readiness. No runtime consumer is
## connected yet: map closure and same-UUID render promotion remain separate gates.
const Products=preload("res://scripts/world3d/collision_product_cache.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Manifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const VERSION:=2
const RULE:="prepared_static_glb_named_nodes_v2"
const MAX_DESCRIPTOR_BYTES:=1024*1024
const MAX_DIRECTORY_BYTES:=32*1024*1024
const MAX_PRODUCTS:=256
const MAX_ENTRIES:=4096
const MAX_RETAINED_BYTES:=128*1024*1024
const HASH_BLOCK_BYTES:=1024*1024
const WORKSPACE_BYTES:=Products.WORKSPACE_BYTES+4*MAX_DESCRIPTOR_BYTES+4*HASH_BLOCK_BYTES
static var enabled:=false
static var _publish_mutex:=Mutex.new()

class Asset extends RefCounted:
	# Kept distinct from Products.Product: source validity alone must never stand
	# in for selected map reference closure, authored overrides or whole buildings.
	var _source_path:=""
	var _source_sha:=""
	var _entries:Array=[]
	var _products:Array=[]
	var _bytes:=0
	func source_path()->String:return _source_path
	func source_sha()->String:return _source_sha
	func entries()->Array:return _entries.duplicate(true)
	func geometry(index:int)->Dictionary:
		return _products[index].duplicate(true) if index>=0 and index<_products.size() else {}
	func retained_bytes()->int:return _bytes

static func generator()->String:
	var values:Array=[VERSION,RULE,Products.generator()]
	for path:String in ["collision_asset_descriptor.gd","collision_asset_builder.gd","asset_bounds_manifest.gd","gltf_map_io.gd","deferred_asset_loader.gd"]:
		values.append(FileAccess.get_sha256("res://scripts/world3d/"+path))
	return JSON.stringify(values).sha256_text()

static func directory(root:String)->String:return Products.directory(root).path_join("assets")
static func _index_path(path:String,root:String)->String:return directory(root).path_join(path.sha256_text()+".json")
static func _product_identity(path:String,digest:String,selector:String,root:String,generation:String)->Dictionary:
	# The adapter's importer/node rules also identify each immutable .rmcp. A
	# directory from generation A must not observe products overwritten by B.
	var source:Dictionary={};source[path]=digest
	return Products.identity(source,"glb/"+generation+"/"+selector,root)
static func _miss(reason:String,cancelled:bool=false)->Dictionary:
	return {"ok":false,"reason":reason,"cancelled":cancelled,"fallback_required":not cancelled}
static func _cancelled(token:RefCounted)->bool:return token!=null and token.is_cancelled()
static func _uint(value:Variant,maximum:int)->bool:
	return (value is int or value is float) and is_finite(float(value)) and value==floor(float(value)) and value>=0 and value<=maximum
static func _finite_pose(value:Variant)->bool:
	return value is Transform3D and value.origin.is_finite() and value.basis.x.is_finite() and value.basis.y.is_finite() and value.basis.z.is_finite() and is_finite(value.basis.determinant()) and value.basis.determinant()!=0

static func _node_path(value:Variant)->bool:
	if not value is String or value.is_empty() or value.length()>4096:return false
	if value==".":return true
	if value.begins_with("/") or ":" in value or "\\" in value:return false
	for part:String in value.split("/",true):
		if part.is_empty() or part in [".",".."]:return false
	return true

static func _valid_candidate(value:Dictionary,path:String,root:String,expected:String="")->bool:
	if value.size()!=9 or root.is_empty() or not Paths.allowed(path,root) or value.get("version")!=VERSION or value.get("source_path")!=path or value.get("generator")!=generator():return false
	if not Products._sha(value.get("source_sha")) or not Products._sha(value.get("descriptor_sha")):return false
	if not expected.is_empty() and value.source_sha!=expected:return false
	if not _uint(value.get("descriptor_bytes"),MAX_DESCRIPTOR_BYTES) or value.descriptor_bytes<=0 or not _uint(value.get("retained_bytes"),MAX_RETAINED_BYTES):return false
	if not _uint(value.get("product_count"),MAX_PRODUCTS) or value.product_count<=0:return false
	return _uint(value.get("estimated_bytes"),MAX_RETAINED_BYTES+WORKSPACE_BYTES) and value.estimated_bytes==value.retained_bytes+WORKSPACE_BYTES

static func candidate(path:String,root:String,expected_source:String="")->Dictionary:
	# Small bounded admission descriptor only; no payload/source read or geometry
	# authority. Freeze this exact envelope and never re-read the mutable index.
	if root.is_empty() or not Paths.allowed(path,root) or not FileAccess.file_exists(path):return {}
	if not expected_source.is_empty() and not Products._sha(expected_source):return {}
	var index:=_index_path(path,root)
	if not Paths.allowed(index,directory(root)):return {}
	var file:=FileAccess.open(index,FileAccess.READ)
	if file==null or file.get_length()<=0 or file.get_length()>4096:return {}
	var bytes:=file.get_buffer(file.get_length());file.close()
	var value:Variant=JSON.parse_string(bytes.get_string_from_utf8())
	if not value is Dictionary or not _valid_candidate(value,path,root,expected_source):return {}
	# JSON numbers are floating point. Validate exact bounded integer values
	# before restoring the scalar API types used by the admission ledger.
	for key:String in ["version","descriptor_bytes","retained_bytes","product_count","estimated_bytes"]:value[key]=int(value[key])
	return value

static func _hash_source(path:String,root:String,token:RefCounted)->Dictionary:
	if _cancelled(token):return _miss("cancelled",true)
	if not Paths.allowed(path,root):return _miss("source_path")
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return _miss("source_missing")
	var length:=file.get_length();var left:=length;var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	while left>0:
		if _cancelled(token):return _miss("cancelled",true)
		var block:=file.get_buffer(mini(left,HASH_BLOCK_BYTES))
		if block.is_empty():return _miss("source_read")
		hash.update(block);left-=block.size()
	if file.get_length()!=length or file.get_error() not in [OK,ERR_FILE_EOF]:return _miss("source_changed")
	file.close()
	if _cancelled(token):return _miss("cancelled",true)
	if not Paths.allowed(path,root) or not FileAccess.file_exists(path):return _miss("source_path")
	return {"ok":true,"sha":hash.finish().hex_encode()}

static func read(value:Dictionary,root:String,admitted_bytes:int,token:RefCounted=null)->Dictionary:
	if not Products._worker():return _miss("worker_required")
	var began:=Time.get_ticks_usec()
	if _cancelled(token):return _miss("cancelled",true)
	var path:String=str(value.get("source_path",""))
	if not _valid_candidate(value,path,root):return _miss("candidate")
	var candidate_end:=Time.get_ticks_usec()
	if admitted_bytes<int(value.estimated_bytes):return _miss("budget_not_admitted")
	var blob:=directory(root).path_join(str(value.descriptor_sha)+".rmca")
	if not Paths.allowed(blob,directory(root)):return _miss("descriptor_path")
	var file:=FileAccess.open(blob,FileAccess.READ)
	if file==null or file.get_length()!=int(value.descriptor_bytes):return _miss("descriptor_length")
	var bytes:=file.get_buffer(int(value.descriptor_bytes));file.close()
	if bytes.size()!=int(value.descriptor_bytes) or Products._digest(bytes)!=value.descriptor_sha:return _miss("descriptor_checksum")
	var data:Variant=bytes_to_var(bytes) # Object/script decoding is never enabled.
	var decode_end:=Time.get_ticks_usec()
	if not data is Dictionary or not _valid_directory(data,value,root):return _miss("descriptor_schema")
	var directory_end:=Time.get_ticks_usec()
	var geometries:Array=[];var retained:=0
	for row:Dictionary in data.products:
		if _cancelled(token):return _miss("cancelled",true)
		var product:=Products.read_candidate(row.identity,root,token)
		if not product.get("ok",false):return _miss("product:"+str(product.reason),_cancelled(token))
		if product.kind!=row.kind or product.bytes!=row.bytes:return _miss("product_layout")
		var bounds:=_bounds(product.faces,product.box)
		if bounds!=row.bounds:return _miss("product_bounds")
		retained+=int(product.bytes)
		if retained>int(value.retained_bytes):return _miss("product_budget")
		geometries.append({"kind":product.kind,"faces":product.faces,"box":product.box,"bounds":bounds,"identity":product.identity})
	if retained!=int(value.retained_bytes):return _miss("product_bytes")
	var products_end:=Time.get_ticks_usec()
	# No GLTF/PackedScene/material/image APIs above. The full current author hash
	# remains the final gate, after every frozen payload has been read/validated.
	var source:=_hash_source(path,root,token)
	var source_end:=Time.get_ticks_usec()
	if not source.ok:return source
	if source.sha!=value.source_sha:return _miss("source_changed")
	if not Paths.allowed(blob,directory(root)) or _cancelled(token):return _miss("path_or_cancel",_cancelled(token))
	var asset:=Asset.new();asset._source_path=path;asset._source_sha=value.source_sha;asset._entries=data.entries;asset._products=geometries;asset._bytes=retained
	return {"ok":true,"asset":asset,"source_digest":source.sha,"retained_bytes":retained,"elapsed_us":Time.get_ticks_usec()-began,"image_decodes":0,"render_imports":0,
		"profile":{"candidate_identity_us":candidate_end-began,"descriptor_read_decode_us":decode_end-candidate_end,"directory_identity_schema_us":directory_end-decode_end,"products_read_validate_us":products_end-directory_end,"final_source_sha_us":source_end-products_end}}

static func _valid_directory(data:Dictionary,value:Dictionary,root:String)->bool:
	if data.size()!=6 or data.get("version")!=VERSION or data.get("generator")!=value.generator or data.get("source_path")!=value.source_path or data.get("source_sha")!=value.source_sha:return false
	if not data.get("entries") is Array or data.entries.is_empty() or data.entries.size()>MAX_ENTRIES or not data.get("products") is Array or data.products.size()!=int(value.product_count):return false
	var total:=0;var products_seen:Dictionary={};var entries_seen:Dictionary={};var paths_seen:Dictionary={};var used:Dictionary={}
	for row:Variant in data.products:
		if not row is Dictionary or row.size()!=5 or not row.get("identity") is Dictionary or row.get("kind") not in ["faces","box"] or not row.get("bounds") is AABB or not _uint(row.get("bytes"),Products.MAX_OUTPUT_BYTES):return false
		if not row.get("selector") is String or row.selector.is_empty() or row.selector.length()>1024 or products_seen.has(row.selector):return false
		if not row.bounds.position.is_finite() or not row.bounds.size.is_finite() or row.bounds.size.x<0 or row.bounds.size.y<0 or row.bounds.size.z<0:return false
		if row.identity!=_product_identity(value.source_path,value.source_sha,row.selector,root,value.generator):return false
		products_seen[row.selector]=true;total+=int(row.bytes)
		if total>int(value.retained_bytes):return false
	for row:Variant in data.entries:
		if not row is Dictionary or row.size()!=5 or not row.get("selector") is String or row.selector.is_empty() or row.selector.length()>1024 or entries_seen.has(row.selector):return false
		if not _node_path(row.get("node_path")) or paths_seen.has(row.node_path.replace("/","__")):return false
		if not _finite_pose(row.get("transform")) or not _uint(row.get("product"),data.products.size()-1) or row.get("collision") not in ["","none","walk","block"]:return false
		entries_seen[row.selector]=true;paths_seen[row.node_path.replace("/","__")]=true;used[int(row.product)]=true
	return total==int(value.retained_bytes) and used.size()==data.products.size()

static func _bounds(faces:PackedVector3Array,box:Vector3)->AABB:
	if box!=Vector3.ZERO:return AABB(-box*.5,box)
	var result:=AABB(faces[0],Vector3.ZERO)
	for vertex:Vector3 in faces:result=result.expand(vertex)
	return result

static func _build_verified_preparation(path:String,root:String,prepared:Dictionary,admitted_workspace:int,token:RefCounted=null)->Dictionary:
	# INTERNAL adapter only. The public collision_asset_builder.build() owns the
	# real import; callers cannot turn a supplied digest/scene dictionary into a
	# producer proof. This helper must not become a runtime publication API.
	# Its existing importer/source transaction owns all GPU/resource allocation.
	# This adapter never captures a mesh, parses GLTF, or destroys those owners.
	if not Products._worker():return _miss("worker_required")
	if admitted_workspace<WORKSPACE_BYTES:return _miss("workspace_not_admitted")
	if root.is_empty() or not Paths.allowed(path,root) or prepared.get("error")!="" or not Products._sha(prepared.get("source_digest")):return _miss("prepared_source")
	var scene:Variant=prepared.get("scene")
	if not scene is Node3D or scene.is_inside_tree() or scene.get_parent()!=null:return _miss("private_scene")
	if _cancelled(token):return _miss("cancelled",true)
	# Reject animation, skins, external dependencies and native-map identities.
	# Accessor bounds are eligibility only; all stored bounds come from faces.
	var manifest:=Manifest.read(path)
	if not manifest.get("known",false):return _miss("unsupported:"+str(manifest.get("reason","")))
	var before:=_hash_source(path,root,token)
	if not before.ok:return before
	if before.sha!=prepared.source_digest:return _miss("source_changed")
	var generation:=generator()
	var products:Array=[];var entries:Array=[];var candidates:Array=[];var seen:Dictionary={};var total:=0
	var nodes:Array=[{"node":scene,"pose":Transform3D.IDENTITY,"selector":"root"}]
	while not nodes.is_empty():
		if _cancelled(token):return _miss("cancelled",true)
		var current:Dictionary=nodes.pop_back();var node:Node=current.node
		if not node is Node3D or node.get_script()!=null or node.has_meta("native_dynamic"):return _miss("unsupported_node")
		var extras:Dictionary=preload("res://scripts/world3d/gltf_map_io.gd").extras_of(node)
		# Dynamic actor allegiance skips ordinary bodies in WorldStream. Keep
		# these sources on that existing route rather than dropping this meaning.
		if bool(extras.get("hostile",false)) or bool(extras.get("ally",false)):return _miss("actor_semantics")
		# No interaction/body metadata may disappear in the collision-only route.
		# UUID is replaced by the map namespace; the collision mode is preserved.
		for extra in extras:
			if extra not in ["uuid","rmmo_collision"]:return _miss("unsupported_node_semantics:"+str(extra))
		var pose:Transform3D=current.pose*node.transform
		if not _finite_pose(pose):return _miss("node_transform")
		if node is MeshInstance3D:
			var mesh:Mesh=node.get_meta("collision_solid",node.get_meta("paint_source",node.mesh))
			var cpu:Variant=mesh if mesh is Cpu else (mesh.get_meta("ground_cpu_cache") if mesh!=null and mesh.has_meta("ground_cpu_cache") else null)
			if not cpu is Cpu:return _miss("prepared_cpu_missing")
			var faces:PackedVector3Array=cpu._collision_faces;var box:Vector3=cpu.box_size
			if box!=Vector3.ZERO:faces=PackedVector3Array()
			if faces.is_empty() and box==Vector3.ZERO:return _miss("prepared_faces_missing")
			var key:int=cpu.get_instance_id();var product_index:int=int(seen.get(key,-1))
			if product_index<0:
				if products.size()>=MAX_PRODUCTS:return _miss("product_limit")
				var identity:=_product_identity(path,before.sha,str(current.selector),root,generation)
				var product:=Products.make_candidate(identity,faces,box)
				if not product.ok:return _miss("product:"+str(product.reason))
				total+=int(product.bytes)
				if total>MAX_RETAINED_BYTES:return _miss("retained_limit")
				product_index=products.size();seen[key]=product_index;candidates.append(product)
				products.append({"selector":current.selector,"identity":identity,"kind":product.kind,"bytes":product.bytes,"bounds":_bounds(faces,box)})
			# Io.extras_of uses the actual importer metadata key; keep the offline
			# adapter aligned rather than guessing from accessor/name conventions.
			var mode:String=str(extras.get("rmmo_collision",""))
			if mode not in ["","none","walk","block"]:return _miss("collision_mode")
			entries.append({"selector":current.selector,"node_path":str(scene.get_path_to(node)),"transform":pose,"product":product_index,"collision":mode})
			if entries.size()>MAX_ENTRIES:return _miss("entry_limit")
		for i in range(node.get_child_count()-1,-1,-1):nodes.append({"node":node.get_child(i),"pose":pose,"selector":str(current.selector)+"/"+str(i)})
	if entries.is_empty():return _miss("empty_scene")
	var data:Dictionary={"version":VERSION,"generator":generation,"source_path":path,"source_sha":before.sha,"products":products,"entries":entries}
	var bytes:=var_to_bytes(data)
	if bytes.size()>MAX_DESCRIPTOR_BYTES:return _miss("descriptor_limit")
	var value:Dictionary={"version":VERSION,"generator":data.generator,"source_path":path,"source_sha":before.sha,"descriptor_sha":Products._digest(bytes),"descriptor_bytes":bytes.size(),"retained_bytes":total,"product_count":products.size(),"estimated_bytes":total+WORKSPACE_BYTES}
	if not _valid_candidate(value,path,root) or not _valid_directory(data,value,root):return _miss("generated_directory")
	for product:Dictionary in candidates:
		var written:=Products._store_bound_candidate(product,root,admitted_workspace,token)
		if not written.ok:return _miss("product_write:"+str(written.reason),_cancelled(token))
	var after:=_hash_source(path,root,token)
	if not after.ok:return after
	if after.sha!=before.sha:return _miss("source_changed")
	return _publish(value,bytes,root,token)

static func _publish(value:Dictionary,bytes:PackedByteArray,root:String,token:RefCounted)->Dictionary:
	var folder:=directory(root)
	if not Paths.allowed(folder,root) or DirAccess.make_dir_recursive_absolute(folder)!=OK:return _miss("directory_path")
	var blob:=folder.path_join(str(value.descriptor_sha)+".rmca")
	var index:=_index_path(value.source_path,root)
	if not Paths.allowed(blob,folder) or not Paths.allowed(index,folder):return _miss("publish_path")
	_publish_mutex.lock()
	var total:=0
	for name:String in DirAccess.get_files_at(folder):
		if name==blob.get_file() or not name.ends_with(".rmca"):continue
		var path:=folder.path_join(name)
		if not Paths.allowed(path,folder):continue
		var file:=FileAccess.open(path,FileAccess.READ)
		if file!=null:total+=file.get_length();file.close()
	var result:=_miss("directory_capacity")
	if total+bytes.size()<=MAX_DIRECTORY_BYTES and not _cancelled(token):
		result=_write_atomic(blob,bytes,folder,token)
		if result.ok:result=_write_atomic(index,JSON.stringify(value).to_utf8_buffer(),folder,token)
	_publish_mutex.unlock()
	if _cancelled(token):return _miss("cancelled",true)
	if result.ok:result.candidate=value
	return result

static func _write_atomic(path:String,bytes:PackedByteArray,folder:String,token:RefCounted)->Dictionary:
	var staged:=path+".%d.%d.%d.tmp"%[OS.get_process_id(),OS.get_thread_caller_id(),Time.get_ticks_usec()]
	if not Paths.allowed(path,folder) or not Paths.allowed(staged,folder):return _miss("publish_path")
	var file:=FileAccess.open(staged,FileAccess.WRITE)
	if file==null:return _miss("write")
	file.store_buffer(bytes);file.flush();var good:=file.get_error()==OK and file.get_position()==bytes.size();file.close()
	var code:int=ERR_SKIP
	if good and not _cancelled(token) and Paths.allowed(path,folder) and Paths.allowed(staged,folder):code=Atomic.publish(staged,path) if FileAccess.file_exists(path) else DirAccess.rename_absolute(staged,path)
	if FileAccess.file_exists(staged):DirAccess.remove_absolute(staged)
	if code==OK and FileAccess.file_exists(path+".previous"):DirAccess.remove_absolute(path+".previous")
	return {"ok":code==OK,"reason":"" if code==OK else "publish","cancelled":_cancelled(token)}
