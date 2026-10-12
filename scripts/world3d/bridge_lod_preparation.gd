extends RefCounted
## Authoring/offline LOD derivation only. Runtime loads restore stored indices;
## they never run mesh simplification. Base arrays and collision stay exact.
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")

static func snapshot(importer:ImporterMesh)->Dictionary:
	var surfaces:Array=[];var lods:Array=[]
	for slot in importer.get_surface_count():
		surfaces.append(importer.get_surface_arrays(slot))
		var levels:Dictionary={}
		for level in importer.get_surface_lod_count(slot):
			levels[importer.get_surface_lod_size(slot,level)]=importer.get_surface_lod_indices(slot,level)
		lods.append(levels)
	return {"surfaces":surfaces,"lods":lods}

static func remember(importer:ImporterMesh,mesh:Mesh)->Mesh:
	# Read the ImporterMesh's CPU arrays, never ask RenderingServer to return
	# the geometry just uploaded by get_mesh(). Includes vertex colors/tangents.
	var data:=snapshot(importer)
	return Cpu.remember(mesh,data.surfaces,data.lods)

static func derive_record(record:Dictionary,token:RefCounted=null)->Dictionary:
	var Frozen=load("res://scripts/world3d/house_prefab.gd")
	if not record.has("bridge_mesh") or not record.has("house_prefab") or not Frozen.valid(record):return {"ok":false,"error":"需要有效的固定石桥"}
	var data:Dictionary=Frozen.decode(record.house_prefab)
	var prepared:=derive_data(data,token)
	if not prepared.ok:return prepared
	if not prepared.changed:return {"ok":true,"changed":false,"record":record}
	var bytes:=var_to_bytes(prepared.data)
	var result:=record.duplicate(true)
	result.house_prefab={"version":1,"sha256":Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
	return {"ok":true,"changed":true,"record":result,"levels":prepared.levels}

static func derive_data(data:Dictionary,token:RefCounted=null)->Dictionary:
	if token!=null and token.is_cancelled():return {"ok":false,"cancelled":true,"error":"LOD 准备已取消"}
	if not Cook.valid_data(data) or data.entries.size()!=1:return {"ok":false,"error":"固定网格数据无效"}
	var render_id:int=data.entries[0][1][0];var source_id:int=data.entries[0][1][1]
	var original:Dictionary=data.meshes[render_id]
	if original.box_size!=Vector3.ZERO:return {"ok":false,"error":"基础盒体不生成桥梁 LOD"}
	if original.get("lods",[]).any(func(levels):return not levels.is_empty()):return {"ok":true,"changed":false,"data":data}
	var arrays:Array=original.surfaces.duplicate(true)
	var before:=var_to_bytes(arrays);var importer:=ImporterMesh.new()
	for surface:Array in arrays:importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,surface)
	importer.generate_lods(60,25,[])
	if token!=null and token.is_cancelled():return {"ok":false,"cancelled":true,"error":"LOD 准备已取消"}
	var generated:=snapshot(importer)
	if var_to_bytes(generated.surfaces)!=before:return {"ok":false,"error":"LOD 生成改变了基础几何，拒绝替换"}
	if not Cook.valid_lods(generated.lods,original.surfaces):return {"ok":false,"error":"生成的 LOD 索引无效"}
	var counts:Array=[];var count:=0
	for levels:Dictionary in generated.lods:counts.append(levels.size());count+=levels.size()
	if count==0:return {"ok":true,"changed":false,"data":data,"levels":counts}
	var result:=data.duplicate(true)
	# Older frozen bridges share render/source indices. Separate only the
	# render row so every byte of the authored collision row remains identical.
	if render_id==source_id:
		result.meshes.append(result.meshes[render_id].duplicate(true));render_id=result.meshes.size()-1
		result.entries[0][1][0]=render_id
	result.meshes[render_id].lods=generated.lods
	if not Cook.valid_data(result) or var_to_bytes(result.meshes[source_id])!=var_to_bytes(data.meshes[source_id]) or var_to_bytes(result.materials)!=var_to_bytes(data.materials):return {"ok":false,"error":"LOD 派生改变了原碰撞或材质"}
	return {"ok":true,"changed":true,"data":result,"levels":counts}
