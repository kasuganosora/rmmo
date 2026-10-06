extends RefCounted
## Original Blender modules -> one procedural mesh, three shared PBR surfaces.
const D=preload("res://scripts/world3d/bridge_data.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
static var kits: Dictionary={}
static var meshes: Dictionary={}
var streams: Array=[]
var materials: Array=[]
var tiles: Array=[]
var data: Dictionary
static func height_at(x: float,d: Dictionary) -> float: return d.camber*pow(sin(PI*clampf(x/d.length+.5,0,1)),2)
static func slope_at(x: float,d: Dictionary) -> float: return d.camber*PI/d.length*sin(TAU*clampf(x/d.length+.5,0,1))
static func kit(path: String) -> Dictionary:
	if kits.has(path): return kits[path]
	if not preload("res://scripts/world3d/map_paths.gd").allowed(path) or not FileAccess.file_exists(path): return {}
	var root: Node3D=preload("res://scripts/world_editor/asset_library.gd").instantiate_preview(path)
	if root==null: return {}
	var pieces:={}
	for node in Paint.meshes(root): pieces[str(node.name)]={"mesh":node.mesh,"transform":node.transform}
	root.free()
	for key in ["arch","pier","abutment","deck","parapet","post"]:
		if not pieces.has(key): return {}
	if kits.size()>=8: kits.erase(kits.keys()[0])
	kits[path]=pieces
	return pieces
func append_piece(piece: Dictionary,position: Vector3,scale_: Vector3,foundation:=false) -> void:
	var mesh: Mesh=piece.mesh
	for slot in mesh.get_surface_count():
		var mat: Material=mesh.surface_get_material(slot); var name_: String=mat.resource_name if mat!=null else ""
		var source_role:=0 if name_.contains("deck") else (2 if name_.contains("trim") else 1)
		var arrays: Array=mesh.surface_get_arrays(slot)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]; var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]; var uvs: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
		var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for i in vertices.size(): indices.append(i)
		var triangle:Array=[]
		for index in indices:
			var p: Vector3=piece.transform*vertices[index]; var normal: Vector3=piece.transform.basis*normals[index]
			p=p*scale_+position; normal=(normal/scale_).normalized()
			# The deck module is a solid slab. Only its upward walking surface
			# is paving; side/end/underside faces belong to supporting masonry.
			var role:int=1 if source_role==0 and normal.y<.7 else source_role
			if foundation: p.y+=(scale_.y-1)*.25
			# Continuous metre-scale paving/masonry avoids one texture restart per module.
			var uv: Vector2=uvs[index]*2/tiles[role]
			if role!=2:
				uv=(Vector2(p.x,p.z) if absf(normal.y)>.7 else (Vector2(p.x,p.y) if absf(normal.z)>.7 else Vector2(p.z,p.y)))/tiles[role]
			# Stretch the supporting masonry above a fixed foundation; no floating piers.
			var f: float=clampf((p.y+data.depth)/(data.depth-.25),0,1) if foundation else 1.0
			var stretch: float=1+height_at(p.x,data)/(data.depth-.25) if foundation and f<1 else 1.0
			normal=Vector3(normal.x-slope_at(p.x,data)*f*normal.y/stretch,normal.y/stretch,normal.z).normalized(); p.y+=height_at(p.x,data)*f
			triangle.append({"p":p,"n":normal,"uv":uv,"color":colors[index] if index<colors.size() else Color.WHITE})
			if triangle.size()==3:
				preload("res://scripts/world3d/bridge_deck_rim.gd").emit(streams,triangle,role,data.width,tiles[1]);triangle=[]
func build(record: Dictionary) -> ArrayMesh:
	var started:=Time.get_ticks_usec()
	streams.clear(); materials.clear(); tiles.clear()
	data=record.bridge_mesh
	var key: String=preload("res://scripts/world3d/city_layout.gd").token([data,record.asset_path,record.bridge_materials])
	if meshes.has(key): return meshes[key]
	var pieces:=kit(record.asset_path)
	if pieces.is_empty(): return null
	var l: float=data.length; var w: float=data.width; var count:=int(data.arches); var pier: float=data.recipe.pier_width
	for role in ["deck","masonry","trim"]:
		var st:=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); streams.append(st)
		var material: StandardMaterial3D=Paint.make_material(record.bridge_materials[role]).duplicate(); material.vertex_color_use_as_albedo=true
		st.set_material(material); materials.append(material)
		var tile: Array=record.bridge_materials[role].get("tile_size",[2,2]); tiles.append(Vector2(tile[0],tile[1]))
	var opening: float=(l-2-(count-1)*pier)/count
	for i in count:
		var x: float=-l*.5+1+i*(opening+pier)+opening*.5
		append_piece(pieces.arch,Vector3(x,0,0),Vector3(opening/8,(data.depth-.25)/4.75,w/7),true)
	for i in count+1:
		var x: float=-l*.5+.5 if i==0 else (l*.5-.5 if i==count else -l*.5+1+i*opening+(i-1)*pier+pier*.5)
		append_piece(pieces.abutment if i==0 or i==count else pieces.pier,Vector3(x,0,0),Vector3(1 if i==0 or i==count else pier/1.3,(data.depth-.25)/4.75,w/7),true)
	var n:=ceili(l/.75); var step:=l/n
	for i in n:
		var x: float=-l*.5+(i+.5)*step
		append_piece(pieces.deck,Vector3(x,0,0),Vector3(step,1,w/7))
	n=ceili(l/1.5); step=l/n
	for i in n:
		var x: float=-l*.5+(i+.5)*step
		for side in [-1,1]: append_piece(pieces.parapet,Vector3(x,0,side*(w*.5-.28)),Vector3(step,data.recipe.rail_height/(.98 if data.recipe.style=="rustic" else 1.08),1))
	for side in [-1,1]:
		for end in [-1,1]: append_piece(pieces.post,Vector3(end*(l*.5-.34),0,side*(w*.5-.28)),Vector3.ONE)
	var importer:=ImporterMesh.new()
	for i in streams.size():
		var st: SurfaceTool=streams[i]; st.generate_tangents(); st.index()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,st.commit_to_arrays(),[],{},materials[i],["bridge_paving","bridge_masonry","bridge_coping_and_arch_rings"][i])
	importer.generate_lods(60,25,[])
	var result:=importer.get_mesh()
	var counts: Array=[]
	for slot in importer.get_surface_count():
		var levels: Array=[]
		for level in importer.get_surface_lod_count(slot): levels.append(importer.get_surface_lod_indices(slot,level).size()/3)
		counts.append(levels)
	result.set_meta("bridge_lods",counts); result.set_meta("bridge_build_ms",(Time.get_ticks_usec()-started)/1000.0)
	if meshes.size()>=6: meshes.erase(meshes.keys()[0])
	meshes[key]=result
	return result
