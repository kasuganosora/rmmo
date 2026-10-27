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
static func height_at(x: float,d: Dictionary) -> float: return d.camber*pow(sin(PI*clampf(x/d.length+.5,0,1)),2)+d.get("rise",0.)*(clampf(x/d.length+.5,0,1)-.5)
static func slope_at(x: float,d: Dictionary) -> float: return d.camber*PI/d.length*sin(TAU*clampf(x/d.length+.5,0,1))+d.get("rise",0.)/d.length
static func repair_zero_tangents(arrays:Array)->Dictionary:
	# MikkTSpace's angle weighting can round a very thin bevel corner to zero
	# even with a non-degenerate position/UV triangle. Recover only those missing
	# bases from that triangle's actual UV derivatives. Never invent an arbitrary
	# axis, remove geometry, alter valid tangents, or change normals/UV mapping.
	var p:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var n:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
	if n.size()!=p.size() or uv.size()!=p.size() or tangents.size()!=p.size()*4:return {"ok":false,"error":"bridge tangent channels missing"}
	var missing:Dictionary={};var best:Dictionary={}
	for i in p.size():
		var t:=Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2])
		if not t.is_finite() or t.length_squared()<.1:missing[i]=true
	if missing.is_empty():return {"ok":true,"repaired":0}
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	if indices.is_empty():
		for i in p.size():indices.append(i)
	for at in range(0,indices.size(),3):
		var a:int=indices[at];var b:int=indices[at+1];var c:int=indices[at+2]
		if not missing.has(a) and not missing.has(b) and not missing.has(c):continue
		var ab:=p[b]-p[a];var ac:=p[c]-p[a];var duv:=uv[b]-uv[a];var dvv:=uv[c]-uv[a]
		var determinant:=duv.cross(dvv);var area:=ab.cross(ac).length_squared()
		if absf(determinant)<1e-20 or area<1e-20:continue
		var along_u:Vector3=(ab*dvv.y-ac*duv.y)/determinant
		var along_v:Vector3=(ac*duv.x-ab*dvv.x)/determinant
		for i:int in [a,b,c]:
			if not missing.has(i) or area<=float(best.get(i,0)):continue
			var normal:=n[i].normalized();var tangent:=along_u-normal*normal.dot(along_u)
			if not tangent.is_finite() or tangent.length_squared()<1e-20:continue
			tangent=tangent.normalized()
			var orientation:=normal.cross(tangent).dot(along_v)
			if not is_finite(orientation) or absf(orientation)<1e-20:continue
			tangents[i*4]=tangent.x;tangents[i*4+1]=tangent.y;tangents[i*4+2]=tangent.z
			# SurfaceTool stores the opposite binormal sign to dP/dv (its UV-Y
			# convention). Keep identical handedness to healthy MikkTSpace bases.
			tangents[i*4+3]=1.0 if orientation<0 else -1.0;best[i]=area
	arrays[Mesh.ARRAY_TANGENT]=tangents
	return {"ok":best.size()==missing.size(),"repaired":best.size(),"unresolved":missing.size()-best.size()}
static func kit(path: String,native_only:bool=false) -> Dictionary:
	if kits.has(path): return kits[path]
	var native_package:bool=native_only and preload("res://scripts/world3d/runtime_package_policy.gd").trusted()
	if native_package:
		if not preload("res://scripts/world3d/map_paths.gd").asset_key_allowed(path):return {}
	elif not preload("res://scripts/world3d/map_paths.gd").allowed(path) or not FileAccess.file_exists(path):return {}
	var root: Node3D=preload("res://scripts/world_editor/asset_library.gd").instantiate_preview(path,native_only)
	if root==null: return {}
	var pieces:={}
	for node in Paint.meshes(root): pieces[str(node.name)]={"mesh":node.mesh,"transform":node.transform}
	root.free()
	for key in ["arch","pier","abutment","deck","parapet","post"]:
		if not pieces.has(key): return {}
	if kits.size()>=8: kits.erase(kits.keys()[0])
	kits[path]=pieces
	return pieces
func append_piece(piece: Dictionary,position: Vector3,scale_: Vector3,foundation:=false,yaw:=0.) -> void:
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
			var turn:=Basis(Vector3.UP,yaw)
			p=turn*(p*scale_)+position; normal=(turn*(normal/scale_)).normalized()
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
			var color:Color=colors[index] if index<colors.size() else Color.WHITE
			var noise:=clampf(.5+.25*sin(p.x*2.7+p.z*1.3+data.get("variation_seed",0))+.25*sin(p.y*4.1-p.x*.7),0,1)
			color=color.lerp(Color(.83,.78,.67),data.get("wear",0.)*noise*.28)
			var damp:=clampf((-p.y+.2)/maxf(data.depth,.1),0,1)*(.35+.65*noise)
			color=color.lerp(Color(.24,.31,.15),data.get("moss",0.)*damp*.55)
			triangle.append({"p":p,"n":normal,"uv":uv,"color":color})
			if triangle.size()==3:
				preload("res://scripts/world3d/bridge_deck_rim.gd").emit(streams,triangle,role,data.width,tiles[1]);triangle=[]
func build(record: Dictionary,native_only:bool=false) -> ArrayMesh:
	var started:=Time.get_ticks_usec()
	streams.clear(); materials.clear(); tiles.clear()
	data=record.bridge_mesh
	var key: String=preload("res://scripts/world3d/city_layout.gd").token([data,record.asset_path,record.bridge_materials])
	if meshes.has(key): return meshes[key]
	var pieces:=kit(record.asset_path,native_only)
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
		append_piece(pieces.arch,Vector3(x,0,0),Vector3((opening+pier if data.recipe.style=="timber" else opening)/8,(data.depth-.25)/4.75,w/7),true)
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
	var wing:float=data.get("wing_length",0.)
	if wing>0:
		for side in [-1,1]:
			for end in [-1,1]:
				var angle:float=-side*end*atan(.6)
				append_piece(pieces.parapet,Vector3(end*(l*.5+wing*.5),0,side*(w*.5-.28+wing*.3)),Vector3(wing*sqrt(1.36),1,1),false,angle)
				append_piece(pieces.post,Vector3(end*(l*.5+wing),0,side*(w*.5-.28+wing*.6)),Vector3.ONE)
	var importer:=ImporterMesh.new()
	for i in streams.size():
		var st: SurfaceTool=streams[i]; st.generate_tangents(); st.index()
		var arrays:=st.commit_to_arrays();var repaired:=repair_zero_tangents(arrays)
		if not repaired.ok:push_error("Bridge tangent basis cannot be recovered: "+str(repaired));return null
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},materials[i],["bridge_paving","bridge_masonry","bridge_coping_and_arch_rings"][i])
	importer.generate_lods(60,25,[])
	var result:=importer.get_mesh()
	preload("res://scripts/world3d/bridge_lod_preparation.gd").remember(importer,result)
	var counts: Array=[]
	for slot in importer.get_surface_count():
		var levels: Array=[]
		for level in importer.get_surface_lod_count(slot): levels.append(importer.get_surface_lod_indices(slot,level).size()/3)
		counts.append(levels)
	result.set_meta("bridge_lods",counts); result.set_meta("bridge_build_ms",(Time.get_ticks_usec()-started)/1000.0)
	if meshes.size()>=6: meshes.erase(meshes.keys()[0])
	meshes[key]=result
	return result
