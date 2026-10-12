extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
func _initialize()->void:run.call_deferred()
func triangles(mesh:Dictionary)->int:
	if mesh.box_size!=Vector3.ZERO:return 12
	var count:=0
	for surface:Array in mesh.surfaces:
		var indices:Variant=surface[Mesh.ARRAY_INDEX]
		count+=int((surface[Mesh.ARRAY_VERTEX].size() if indices==null or indices.is_empty() else indices.size())/3)
	return count
func run()->void:
	var path:String=OS.get_cmdline_user_args()[0];var doc=Doc.open_file(path)
	if doc==null:push_error("review map cannot reopen");quit(1);return
	var records:Array=[];var images:Dictionary={};var unique:Dictionary={}
	for record:Dictionary in doc.records:
		if not record.has("house_prefab"):continue
		var data:Dictionary=Frozen.decode(record.house_prefab)
		if data.is_empty():push_error("frozen record decode failed");quit(1);return
		var render_base:=0;var collision_base:=0;var surfaces:=0
		for entry:Array in data.entries:
			var render:Dictionary=data.meshes[entry[1][0]];var collision:Dictionary=data.meshes[entry[1][1]]
			render_base+=triangles(render);collision_base+=triangles(collision);surfaces+=render.surfaces.size()
		for mesh:Dictionary in data.meshes:
			var levels:Array=[]
			for surface:Dictionary in mesh.get("lods",[]):
				var counts:Array=[]
				for error:float in surface:counts.append({"error":error,"triangles":surface[error].size()/3})
				levels.append(counts)
			var key:String=str(mesh.box_size)+":"+preload("res://scripts/world3d/ground_cpu_mesh.gd").geometry_signature(mesh.surfaces,mesh.get("lods",[]))
			unique[key]={"base_triangles":triangles(mesh),"levels_per_surface":levels}
		for material:Dictionary in data.materials:
			for field:String in Frozen.TEXTURE_PROPERTIES:
				var source:String=material.get("paint",{}).get(field,"")
				if source.is_empty() or images.has(source):continue
				var image:=Image.load_from_file(source)
				if image==null:push_error("texture decode failed "+source);quit(1);return
				var size_bytes:=image.get_data_size();var mip:=image.duplicate();mip.generate_mipmaps()
				images[source]={"sha256":FileAccess.get_sha256(source),"encoded_bytes":FileAccess.get_file_as_bytes(source).size(),"dimensions":[image.get_width(),image.get_height()],"decoded_format":image.get_format(),"decoded_bytes":size_bytes,"same_format_with_mips_bytes":mip.get_data_size()}
		records.append({"id":record.uuid,"sha256":record.house_prefab.sha256,"compressed_bytes":Marshalls.base64_to_raw(record.house_prefab.data).size(),"uncompressed_bytes":record.house_prefab.length,"render_base_triangles":render_base,"collision_base_triangles":collision_base,"render_surfaces":surfaces,"fixture":record.get("fixture",{})})
	var result:={"map":path,"map_sha256":FileAccess.get_sha256(path),"frozen_records":records,"unique_geometry":unique,"images":images,"memory_note":"Image bytes are measured decoder buffers. Same-format mip byte totals are a budget, not measured GPU VRAM/RSS. Mesh base and per-surface LOD counts are separate, not added as a visible frame count."}
	var report:=path.get_base_dir().path_join("resource_audit.json")
	FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("WATER_CROWN_RESOURCE_AUDIT ",report);quit(0)
