extends RefCounted
## Immutable authoring data and display geometry. Mutable body state stays local.
const VERSION=1
static var entries:Dictionary={}
static var material_bundles:Dictionary={}
static var preload_pending:Dictionary={}
static var preloaded:Dictionary={}

static func begin_preload()->void:
	if not bool(ProjectSettings.get_setting("rmmo/characters_3d",true)):return
	var folder:=preload("res://scripts/asset/art_paths.gd").path("characters/base/female_base_v2")
	for name:String in ["axis_runtime_materials.res","axis_runtime_mesh.res"]:
		var path:=folder+"/"+name
		if preloaded.has(path) or preload_pending.has(path) or not FileAccess.file_exists(path):continue
		if ResourceLoader.load_threaded_request(path)==OK:preload_pending[path]=true

static func poll_preload()->bool:
	for path:String in preload_pending.keys():
		var status:=ResourceLoader.load_threaded_get_status(path)
		if status==ResourceLoader.THREAD_LOAD_IN_PROGRESS:continue
		if status==ResourceLoader.THREAD_LOAD_LOADED:
			# Retain the immutable resource so later load() calls hit Godot's cache.
			preloaded[path]=ResourceLoader.load_threaded_get(path)
		preload_pending.erase(path)
	return preload_pending.is_empty()

static func material_signature(folder:String)->Array:
	var paths:Array[String]=[folder+"/female_base_v2_display.glb","res://scripts/char/character_regional_skin.gd","res://scripts/char/character_native_face.gd"]
	var asset_root:=folder.get_base_dir().get_base_dir()
	for name:String in ["skin_porcelain_01","eyes_brown_01","face_native_01"]:
		var directory:=asset_root+"/materials/"+name
		for file in DirAccess.get_files_at(directory):paths.append(directory+"/"+file)
	paths.sort()
	var result:Array=[VERSION]
	for path in paths:result.append([path.get_file(),FileAccess.get_sha256(path)])
	return result

static func build_materials()->Dictionary:
	var modes:Dictionary={}
	for screen_space_sss in [false,true]:
		var source:=preload("res://scripts/char/character_regional_skin.gd").create_preview(screen_space_sss)
		assert(source!=null)
		var materials:Dictionary={}
		for mesh:MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
			for surface in mesh.mesh.get_surface_count():materials[mesh.mesh.surface_get_material(surface).resource_name]=mesh.get_surface_override_material(surface)
		modes[screen_space_sss]={"materials":materials,"skin_id":source.get_meta("skin_id",""),"eye_id":source.get_meta("eye_id","")}
		source.free()
	return modes

static func get_materials(folder:String,screen_space_sss:bool)->Dictionary:
	poll_preload()
	if not material_bundles.has(folder):
		var path:=folder+"/axis_runtime_materials.res"
		var bundle:Resource=load(path) if FileAccess.file_exists(path) else null
		if bundle!=null and bundle.get_meta("signature",[])==material_signature(folder):
			material_bundles[folder]=bundle.get_meta("modes")
		else:material_bundles[folder]=build_materials()
	return material_bundles[folder][screen_space_sss]

static func signature(folder:String)->Array:
	return [VERSION,FileAccess.get_sha256(folder+"/female_axis_rig.json"),FileAccess.get_sha256(folder+"/female_display_topology.json")]

static func get_assets(folder:String)->Dictionary:
	if entries.has(folder):return entries[folder]
	var stamp:=signature(folder)
	var data:Dictionary={}
	var path:=folder+"/axis_runtime_data.bin"
	if FileAccess.file_exists(path):
		var file:=FileAccess.open(path,FileAccess.READ)
		var value:Variant=file.get_var(false)
		if value is Dictionary and value.get("signature")==stamp and value.has("rig") and value.has("topology"):
			data=value
	if data.is_empty():
		data={"signature":stamp,"rig":JSON.parse_string(FileAccess.get_file_as_string(folder+"/female_axis_rig.json")),"topology":JSON.parse_string(FileAccess.get_file_as_string(folder+"/female_display_topology.json"))}
	else:
		var mesh_path:=folder+"/axis_runtime_mesh.res"
		if FileAccess.file_exists(mesh_path) and data.get("mesh_sha256","")==FileAccess.get_sha256(mesh_path):data["mesh"]=load(mesh_path)
	if not data.get("mesh") is ArrayMesh:
		if not data.topology.has("display_points"):
			data.topology=JSON.parse_string(FileAccess.get_file_as_string(folder+"/female_display_topology.json"))
		data["mesh"]=build_mesh(data.topology)
	# Original weight tables are immutable across wearers. Only node poses and
	# adapted bind frames need per-instance dictionaries.
	for node:Dictionary in data.rig.nodes:
		for weight:Dictionary in node.weights:
			weight["axis_weights"]=Vector3(weight.xweight,weight.yweight,weight.zweight)
			weight["left"]=Vector3(weight.xleftbulge,weight.yleftbulge,weight.zleftbulge)
			weight["right"]=Vector3(weight.xrightbulge,weight.yrightbulge,weight.zrightbulge)
			weight.make_read_only()
		node.weights.make_read_only();node.full.make_read_only();node.bulge.make_read_only()
	entries[folder]=data
	return data

static func build_mesh(topology:Dictionary)->ArrayMesh:
	var mesh:=ArrayMesh.new()
	for surface in topology.surfaces:
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for quad:Array in surface:
			for corner in [0,1,2,0,2,3]:
				var vertex:int=quad[0][corner];var p:Array=topology.display_points[vertex];var uv:Array=quad[1][corner];var span:Array=topology.ranges[vertex]
				st.set_uv(Vector2(uv[0],1.0-uv[1]));st.set_uv2(Vector2(span[0],span[1]));st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(p[0],p[1],p[2]))
		st.index();st.generate_tangents();st.commit(mesh)
	return mesh
