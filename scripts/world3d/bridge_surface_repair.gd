extends RefCounted
## Maintenance of frozen bridge visuals; authored collision is kept byte-exact.
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Bridge=preload("res://scripts/world3d/bridge_mesh.gd")
static func repair(record:Dictionary)->Dictionary:
	if not record.has("bridge_mesh") or not record.has("house_prefab"):return {"ok":false,"error":"需要固定石桥"}
	var original:=Frozen.geometry(record)
	if original.is_empty() or original.mesh.get_surface_count()!=3:return {"ok":false,"error":"未知桥梁材质布局"}
	var streams:Array=[]
	for slot in 3:
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);streams.append(st)
	var moved:=0;var total:=0
	var tile:Array=record.bridge_materials.masonry.get("tile_size",[2,2])
	for slot in 3:
		var arrays:Array=original.mesh.surfaces[slot]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		if indices.is_empty():
			for i in vertices.size():indices.append(i)
		for face in range(0,indices.size(),3):
			var normal:=Vector3.ZERO
			for j in 3:normal+=arrays[Mesh.ARRAY_NORMAL][indices[face+j]]
			var side:bool=slot==0 and normal.normalized().y<.7
			var target:int=1 if side else slot
			if side:moved+=1
			total+=1
			var triangle:Array=[]
			for j in 3:
				var i:int=indices[face+j];var p:Vector3=vertices[i];var n:Vector3=arrays[Mesh.ARRAY_NORMAL][i]
				var uv:Vector2=arrays[Mesh.ARRAY_TEX_UV][i]
				if side:
					var base_y:float=p.y-Bridge.height_at(p.x,record.bridge_mesh)
					uv=(Vector2(p.x,p.z) if absf(n.y)>.7 else (Vector2(p.x,base_y) if absf(n.z)>.7 else Vector2(p.z,base_y)))/Vector2(tile[0],tile[1])
				triangle.append({"p":p,"n":n,"uv":uv,"color":arrays[Mesh.ARRAY_COLOR][i] if arrays[Mesh.ARRAY_COLOR]!=null else Color.WHITE})
			moved+=preload("res://scripts/world3d/bridge_deck_rim.gd").emit(streams,triangle,target,record.bridge_mesh.width,Vector2(tile[0],tile[1]))
	if moved==0:return {"ok":true,"changed":false,"record":record,"moved_triangles":0}
	var importer:=ImporterMesh.new()
	for slot in 3:
		var st:SurfaceTool=streams[slot];st.index();st.generate_tangents()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,st.commit_to_arrays(),[],{},original.mesh.materials[slot])
	importer.generate_lods(60,25,[])
	var visual:Mesh=importer.get_mesh();var cpu:Mesh=Frozen.Cpu.capture(visual)
	var cache:Dictionary={};cache[[0]]={"mesh":cpu,"source":original.source}
	var data:=Frozen.Cook.pack(cache,"","bridge_surface_v2");Frozen.compact_data(data)
	if data.entries.size()!=1:return {"ok":false,"error":"无法保存修复网格"}
	var bytes:=var_to_bytes(data);var result:Dictionary=record.duplicate(true)
	result.house_prefab={"version":1,"sha256":Frozen.Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
	result.prefab_materials=[]
	for material:Dictionary in data.materials:
		if material.has("paint") and not result.prefab_materials.has(material.paint):result.prefab_materials.append(material.paint)
	return {"ok":true,"changed":true,"record":result,"moved_triangles":moved,"triangles":total}
