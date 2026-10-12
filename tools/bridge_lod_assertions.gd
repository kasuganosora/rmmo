extends RefCounted
## Test-only readback of the actual renderer surface, not CPU metadata or the
## generator's bridge_lods annotation. API/schema verified against ed1daf0bf.
static func matches(mesh:Mesh,expected:Array)->bool:
	if not mesh is ArrayMesh or mesh.get_surface_count()!=expected.size():return false
	RenderingServer.force_sync()
	for slot in expected.size():
		var surface:Dictionary=RenderingServer.mesh_get_surface(mesh.get_rid(),slot)
		var actual:Array=surface.get("lods",[])
		if actual.size()!=expected[slot].size():return false
		var stride:int=RenderingServer.mesh_surface_get_format_index_stride(surface.format,surface.vertex_count)
		for row:Dictionary in actual:
			var distance:float=row.edge_length;var selected:Variant=null
			for key:float in expected[slot]:
				if is_equal_approx(key,distance):selected=expected[slot][key];break
			if selected==null or row.index_data.size()!=selected.size()*stride:return false
			for i in selected.size():
				var index:int=row.index_data.decode_u16(i*2) if stride==2 else row.index_data.decode_u32(i*4)
				if index!=selected[i]:return false
	return true
