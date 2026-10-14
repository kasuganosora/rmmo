extends SceneTree
## Read-only, five-bridge CPU audit. GPU views/batching and native save/reopen are
## deliberately separate evidence supplied by the builder/runtime review.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Ports=preload("res://scripts/world3d/road_bridges.gd")
const Bridge=preload("res://scripts/world3d/bridge_data.gd")
const BridgeMesh=preload("res://scripts/world3d/bridge_mesh.gd")
const BridgeTools=preload("res://scripts/world_editor/bridge_tools.gd")
const DEFAULT_MAP="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const DEFAULT_OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014/bridge_assets"

func _initialize()->void: run.call_deferred()

static func file_identity(path:String)->Dictionary:
	if not FileAccess.file_exists(path): return {"path":path,"exists":false}
	var f:=FileAccess.open(path,FileAccess.READ)
	return {"path":path,"exists":f!=null,"sha256":FileAccess.get_sha256(path),"bytes":f.get_length() if f!=null else 0}

static func demand(condition:bool,label:String,errors:Array)->void:
	if not condition: errors.append(label)

static func mip_rgba8(w:int,h:int)->int:
	var total:=0
	while true:
		total+=w*h*4
		if w==1 and h==1: return total
		w=maxi(1,w/2);h=maxi(1,h/2)
	return total

static func texture_audit(path:String)->Dictionary:
	var row:=file_identity(path)
	if not row.exists:return row
	var image:=Image.load_from_file(path)
	row.decoded=image!=null
	if image==null:return row
	row.dimensions=[image.get_width(),image.get_height()]
	row.decoded_format=image.get_format();row.decoded_bytes=image.get_data_size()
	row.rgba8_with_mips_conservative_bytes=mip_rgba8(image.get_width(),image.get_height())
	var mip:Image=image.duplicate();var error:=mip.generate_mipmaps()
	row.same_format_with_mips_bytes=mip.get_data_size();row.mipmap_generation_error=error
	row.rgba8_or_native_mips_conservative_bytes=maxi(row.rgba8_with_mips_conservative_bytes,mip.get_data_size())
	return row

static func material_audit(value:Dictionary,images:Dictionary,errors:Array,label:String)->Dictionary:
	var paint:Dictionary=value.get("paint",{})
	var row:={"serialized":value,"texture_bindings":{},"native_restoration_checked":false}
	if paint.is_empty():
		errors.append(label+": frozen bridge material lacks editable paint definition")
		return row
	if not Paint.material_valid(paint):
		errors.append(label+": invalid paint")
		return row
	for field:String in Frozen.TEXTURE_PROPERTIES:
		var path:String=paint.get(field,"")
		if path.is_empty():continue
		if not images.has(path):images[path]=texture_audit(path)
		row.texture_bindings[field]={"path":path,"sha256":images[path].get("sha256",""),"color_space":"sRGB" if field=="texture_path" else "linear"}
		demand(images[path].get("decoded",false),label+": texture cannot decode "+path,errors)
	# Native material construction is also supported by Godot's headless renderer.
	# This checks flags/binding identity, not GPU shading or visual quality.
	var material:=Paint.make_material(paint,int(value.get("cull",0)))
	if value.get("vertex_color",false):
		material=material.duplicate();material.vertex_color_use_as_albedo=true
	row.native_restoration_checked=true
	row.normal_enabled=material.normal_enabled;row.normal_texture_bound=material.normal_texture!=null
	row.normal_scale=material.normal_scale;row.normal_format=paint.get("normal_format","opengl")
	row.vertex_color_use_as_albedo=material.vertex_color_use_as_albedo
	row.roughness=material.roughness;row.metallic=material.metallic;row.cull_mode=material.cull_mode
	row.texture_repeat=material.texture_repeat;row.texture_filter=material.texture_filter
	row.transparency=material.transparency;row.ao_enabled=material.ao_enabled
	demand(paint.get("normal_path","").is_empty() or material.normal_enabled and material.normal_texture!=null,label+": normal map disabled",errors)
	return row

static func surface_audit(arrays:Array,normal_required:bool,deck:bool,width:float)->Dictionary:
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL]!=null else PackedVector3Array()
	var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
	var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	var invalid:=0;var rim:=0;var degenerate_tangents:=0;var bytes:=0
	for p:Vector3 in vertices:
		if not p.is_finite():invalid+=1
		if deck and absf(p.z)>width*.5-.5+.0001:rim+=1
	for n:Vector3 in normals:
		if not n.is_finite() or n.length_squared()<.5:invalid+=1
		if deck and n.y<.7:rim+=1
	for p:Vector2 in uv:
		if not p.is_finite():invalid+=1
	for i in range(0,tangents.size(),4):
		var t:=Vector3(tangents[i],tangents[i+1],tangents[i+2])
		if not t.is_finite() or not is_finite(tangents[i+3]):invalid+=1
		if t.length_squared()<.1:degenerate_tangents+=1
	for channel:Variant in arrays:
		if channel!=null:bytes+=channel.to_byte_array().size()
	var okay:=invalid==0 and uv.size()==vertices.size() and normals.size()==vertices.size()
	if normal_required:okay=okay and tangents.size()==vertices.size()*4 and degenerate_tangents==0
	return {"vertices":vertices.size(),"triangles":(indices.size() if not indices.is_empty() else vertices.size())/3,"indices":indices.size(),"uv_count":uv.size(),"normal_count":normals.size(),"tangent_components":tangents.size(),"cpu_channel_bytes":bytes,"invalid_values":invalid,"degenerate_tangents":degenerate_tangents,"normal_map_requires_tangent_basis":normal_required,"attribute_check_passed":okay,"deck_role":deck,"white_rim_bad_vertices_or_normals":rim}

static func mesh_triangles(mesh:Dictionary)->int:
	if mesh.get("box_size",Vector3.ZERO)!=Vector3.ZERO:return 12
	var triangles:=0
	for arrays:Array in mesh.surfaces:
		var indices:Variant=arrays[Mesh.ARRAY_INDEX]
		triangles+=int((arrays[Mesh.ARRAY_VERTEX].size() if indices==null or indices.is_empty() else indices.size())/3)
	return triangles

static func camera_view(pose:Transform3D,target:Vector3,offset:Vector3)->Dictionary:
	var center:=pose*target;var eye:=pose*(target+offset);var delta:=eye-center
	return {"eye":City.xyz(eye),"target":City.xyz(center),"camera":{"projection":"perspective","center":City.xyz(center),"distance":delta.length(),"yaw":rad_to_deg(atan2(delta.x,delta.z)),"pitch":-rad_to_deg(asin(delta.y/delta.length()))}}

static func capture_plan(record:Dictionary)->Dictionary:
	var d:Dictionary=record.bridge_mesh;var length_:float=d.length;var width:float=d.width
	var pose:=Transform3D(Basis.from_euler(City.vec(record.rotation)*PI/180).scaled(City.vec(record.size)),City.vec(record.position))
	var near_x:float=-length_*.3;var near_y:=BridgeMesh.height_at(near_x,d)
	var views:={
		"near":camera_view(pose,Vector3(near_x,near_y+.2,0),Vector3(-4,3.2,width*.5+7)),
		"mid":camera_view(pose,Vector3(0,-.7,0),Vector3(-length_*.25,maxf(6,length_*.19),maxf(22,length_*.85))),
		"far":camera_view(pose,Vector3(0,-.7,0),Vector3(-length_*.6,maxf(18,length_*.65),length_*2.2)),
		"detail":camera_view(pose,Vector3(0,float(d.camber)-.12,width*.5),Vector3(-1.2,1.1,4.2))}
	return {"id":record.uuid,"frozen_payload_sha256":record.house_prefab.sha256,"views":views,"detail_purpose":"side masonry / top paving boundary beneath parapet, former white stripe, arch ring and normal-map density","visibility_caveat":"CPU camera proposal; verify occlusion and terrain/water clipping in actual GPU capture; keep common lighting, exposure and FOV"}

static func audit_document(doc,map_path:String="")->Dictionary:
	var errors:Array=[];var images:Dictionary={};var material_pool:Dictionary={};var unique_geometry:Dictionary={}
	var report:={"schema_version":1,"scope":"five generated stone bridges only","map":file_identity(map_path),"bridges":[],"capture_plan":[],"errors":errors}
	var refs:Dictionary={}
	if FileAccess.file_exists(map_path):
		var gltf:Variant=JSON.parse_string(FileAccess.get_file_as_string(map_path))
		if gltf is Dictionary:
			for node:Dictionary in gltf.get("nodes",[]):
				for compact:Dictionary in node.get("extras",{}).get("rmmo_records",[]):refs[compact.uuid]=compact
	var bridges:Array=doc.records.filter(func(r):return r.has("bridge_mesh"))
	bridges.sort_custom(func(a,b):return a.position[2]<b.position[2])
	demand(bridges.size()==5,"expected exactly five authored bridges; found "+str(bridges.size()),errors)
	var ports:=Ports.resolve(City.resolve(doc.map_meta));report.road_bindings_valid=ports.get("ok",false)
	demand(report.road_bindings_valid,"native road bridge bindings invalid: "+str(ports.get("error","")),errors)
	var support:Array=doc.records.filter(func(r):return r.has("terrain_mesh") or r.has("road_mesh") or r.get("kind")=="box" and r.get("surface_id") in ["ground","grass","dirt","sand","stone","river_bank","river_bed"])
	var total_render:=0;var total_collision:=0;var total_surfaces:=0
	for record:Dictionary in bridges:
		var label:String=record.uuid;var d:Dictionary=record.bridge_mesh
		var row:={"id":label,"name":record.get("editor_name",""),"recipe":d,"source_module_glb":file_identity(record.asset_path),"mesh_buffers":[],"materials":[],"head_support":[]}
		demand(row.source_module_glb.exists,label+": module source GLB missing",errors)
		demand(Bridge.valid(record),label+": native dimensions invalid",errors)
		var payload:Dictionary=record.get("house_prefab",{});var data:=Frozen.decode(payload)
		demand(not data.is_empty(),label+": frozen geometry checksum/decode/structure invalid",errors)
		if data.is_empty():report.bridges.append(row);continue
		row.frozen_payload={"sha256":payload.sha256,"decoded_bytes":payload.length,"zstd_bytes":Marshalls.base64_to_raw(payload.data).size(),"data_generator":data.get("generator","")}
		row.geometry_identity_note="Assembled bridge geometry is the checksum-verified frozen native payload, not the reusable module GLB. No extra GLB is exported by this audit."
		var ref:Dictionary=refs.get(label,{}).get("rmmo_ref",{})
		if not ref.is_empty():
			var path:=map_path.get_base_dir().path_join(ref.uri);row.native_resource=file_identity(path)
			row.native_resource.expected_sha256=ref.sha256;row.native_resource.expected_bytes=ref.length
			demand(row.native_resource.get("sha256","")==ref.sha256 and row.native_resource.get("bytes",0)==int(ref.length),label+": native disk resource signature mismatch",errors)
		else:row.native_resource={"status":"pending native save or inline record","present_on_disk":refs.has(label)}
		for mi in data.materials.size():
			var value:Dictionary=data.materials[mi];var key:=City.token(value)
			if not material_pool.has(key):material_pool[key]=material_audit(value,images,errors,label+" material "+str(mi))
			row.materials.append(material_pool[key].merged({"index":mi}))
		var render_indices:Array=[];var collision_indices:Array=[];var render_triangles:=0;var collision_triangles:=0;var surfaces:=0
		for entry:Array in data.entries:
			render_indices.append(entry[1][0]);collision_indices.append(entry[1][1])
			render_triangles+=mesh_triangles(data.meshes[entry[1][0]])
			collision_triangles+=mesh_triangles(data.meshes[entry[1][1]])
			surfaces+=data.meshes[entry[1][0]].surfaces.size()
		for mi in data.meshes.size():
			var mesh:Dictionary=data.meshes[mi]
			var key:String=str(mesh.box_size)+":"+Cpu.geometry_signature(mesh.surfaces,mesh.get("lods",[]))
			var mesh_row:={"index":mi,"geometry_identity":key,"render_references":render_indices.count(mi),"collision_references":collision_indices.count(mi),"base_triangles":mesh_triangles(mesh),"box_size":City.xyz(mesh.box_size),"surfaces":[],"lods_per_surface":[]}
			var channel_bytes:=0;var lod_bytes:=0
			for si in mesh.surfaces.size():
				var material:Dictionary=row.materials[mesh.materials[si]]
				var deck:bool=material.serialized.get("paint",{})==record.bridge_materials.get("deck",{})
				var rendered:bool=mi in render_indices
				var surface:=surface_audit(mesh.surfaces[si],rendered and material.get("normal_enabled",false),rendered and deck,float(d.width))
				surface.material_index=mesh.materials[si];surface.index=si;channel_bytes+=surface.cpu_channel_bytes
				mesh_row.surfaces.append(surface)
				if rendered:
					demand(surface.attribute_check_passed,label+": render UV/normal/tangent invalid "+str([mi,si]),errors)
					demand(surface.white_rim_bad_vertices_or_normals==0,label+": paving reaches visible side/rim "+str([mi,si]),errors)
			for levels:Dictionary in mesh.get("lods",[]):
				var rows:Array=[];var thresholds:Array=levels.keys();thresholds.sort()
				for threshold:float in thresholds:
					rows.append({"screen_error":threshold,"triangles":levels[threshold].size()/3,"index_bytes":levels[threshold].size()*4});lod_bytes+=levels[threshold].size()*4
				mesh_row.lods_per_surface.append(rows)
			mesh_row.cpu_channel_bytes=channel_bytes;mesh_row.lod_index_bytes=lod_bytes
			unique_geometry[key]={"base_triangles":mesh_row.base_triangles,"cpu_channel_bytes":channel_bytes,"lod_index_bytes":lod_bytes}
			row.mesh_buffers.append(mesh_row)
		row.expanded_render_triangles=render_triangles;row.expanded_collision_triangles=collision_triangles;row.render_surface_instances=surfaces
		total_render+=render_triangles;total_collision+=collision_triangles;total_surfaces+=surfaces
		var pose:=Transform3D(Basis.from_euler(City.vec(record.rotation)*PI/180).scaled(City.vec(record.size)),City.vec(record.position))
		for end in [-1,1]:
			for z in [-float(d.width)*.5+.6,0.,float(d.width)*.5-.6]:
				var p:=pose*Vector3(end*(float(d.length)*.5+.06),end*float(d.get("rise",0))*.5,z)
				var h:=BridgeTools.ground_height(support,p);var okay:=is_finite(h) and absf(h-p.y)<=.12
				row.head_support.append({"point":City.xyz(p),"ground_y":h if is_finite(h) else null,"height_delta":h-p.y if is_finite(h) else null,"passed":okay})
				demand(okay,label+": bridgehead support mismatch "+str([end,z]),errors)
		row.clear_width_m=float(d.width)-1.16;row.max_centerline_grade=(float(d.camber)*PI+absf(float(d.get("rise",0))))/float(d.length)
		var bindings:Array=ports.get("portals",[]).filter(func(port):return port.get("deck_id","")==label)
		row.bindings=bindings
		demand(bindings.size()==1 and bindings[0].get("signature","")==City.token(record),label+": missing/stale bridge binding identity",errors)
		row.editable_semantics={"independent_uuid":label,"collision":record.get("collision",""),"prefab_locked":record.get("prefab_locked",false),"record_locked":record.get("locked",false),"record_hidden":record.get("hidden",false),"group":record.get("group",""),"scope":"whole bridge remains selectable/transformable; fixed prefab prevents structural regeneration; no independent animated parts expected"}
		demand(record.get("collision","")=="walk" and record.get("prefab_locked",false),label+": frozen/walk semantics missing",errors)
		report.bridges.append(row);report.capture_plan.append(capture_plan(record))
	var texture_unique:Dictionary={};var encoded:=0;var decoded:=0;var conservative:=0;var mip_measured:=0
	for path:String in images:
		var texture:Dictionary=images[path];var sha:String=texture.get("sha256",path)
		if texture_unique.has(sha):continue
		texture_unique[sha]=path;encoded+=texture.get("bytes",0);decoded+=texture.get("decoded_bytes",0)
		conservative+=texture.get("rgba8_or_native_mips_conservative_bytes",0);mip_measured+=texture.get("same_format_with_mips_bytes",0)
	report.textures=images;report.unique_geometry=unique_geometry
	var unique_triangles:=0;var unique_mesh_bytes:=0;var unique_lod_bytes:=0
	for geometry:Dictionary in unique_geometry.values():
		unique_triangles+=geometry.base_triangles;unique_mesh_bytes+=geometry.cpu_channel_bytes;unique_lod_bytes+=geometry.lod_index_bytes
	report.totals={"bridge_instances":bridges.size(),"expanded_render_base_triangles":total_render,"expanded_collision_base_triangles":total_collision,"render_surface_instances_before_batching":total_surfaces,"unique_geometry_buffers":unique_geometry.size(),"unique_geometry_base_triangles":unique_triangles,"unique_geometry_channel_bytes":unique_mesh_bytes,"unique_lod_index_bytes":unique_lod_bytes,"unique_texture_contents":texture_unique.size(),"texture_encoded_bytes":encoded,"texture_decoded_bytes":decoded,"texture_same_format_mips_bytes":mip_measured,"texture_rgba8_or_native_mips_conservative_bytes":conservative}
	report.memory_note="Measured encoded files and CPU decoded buffers; mip totals are shared-content budgets, not actual VRAM/RSS/whole-process peaks. LOD indices are listed separately and never summed as simultaneously visible triangles. Static renderer batches are measured by the builder."
	report.status={"resource_cpu":"passed" if errors.is_empty() else "failed","visual":"pending actual GPU near/mid/far/detail review","pipeline":"frozen checksum and native material flags audited; save/reopen identity and real HTTP authoring evidenced by builder","integration":"candidate/formal status and outdoor capsule traversal evidenced by builder/runtime review"}
	report.passed=errors.is_empty()
	return report

static func write_report(doc,map_path:String,out:String)->Dictionary:
	var result:=audit_document(doc,map_path)
	DirAccess.make_dir_recursive_absolute(out)
	var file:=FileAccess.open(out.path_join("resource_audit.json"),FileAccess.WRITE)
	if file==null:return {"passed":false,"errors":["cannot write resource_audit.json"]}
	file.store_string(JSON.stringify(result,"\t"));file.close()
	file=FileAccess.open(out.path_join("bridge_capture_plan.json"),FileAccess.WRITE)
	if file==null:return {"passed":false,"errors":["cannot write bridge_capture_plan.json"]}
	file.store_string(JSON.stringify({"requested_window_size":[1600,1000],"actual_image_dimensions":"Use build.images for each captured viewport image; window size is not image resolution.","image_format":"lossy WebP quality 90 before viewing/upload","lighting":"common saved environment, exposure and FOV; hide character rendering and all authoring helpers, retain collision","bridges":result.capture_plan},"\t"));file.close()
	return result

func run()->void:
	var map_path:=DEFAULT_MAP;var out:=DEFAULT_OUT
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_path=arg.trim_prefix("--map=")
		elif arg.begins_with("--out="):out=arg.trim_prefix("--out=")
	var before:=FileAccess.get_sha256(map_path);var doc=Doc.open_file(map_path)
	if doc==null:push_error("Cannot natively open bridge audit map");quit(1);return
	var result:=write_report(doc,map_path,out)
	if FileAccess.get_sha256(map_path)!=before:push_error("Source map changed during read-only audit");quit(1);return
	print("AXEL_BRIDGE_AUDIT ",JSON.stringify({"passed":result.passed,"totals":result.get("totals",{}),"errors":result.get("errors",[]),"out":out}))
	quit(0 if result.passed else 1)
