extends SceneTree
## Read-only frozen-native castle model cost/attribute audit; GPU is separate.
const Doc=preload("res://scripts/world3d/world_document.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Audit=preload("res://tools/audit_axel_bridge_assets.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
var path:="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf"
func _init()->void:call_deferred("run")
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):path=arg.trim_prefix("--map=")
	var hash_before:=FileAccess.get_sha256(path);var doc=Doc.open_file(path)
	if doc==null:push_error("Cannot open native fortification map");quit(1);return
	var errors:Array=[];var pending:Array=[];var rows:Array=[];var images:Dictionary={};var materials:Dictionary={};var unique:Dictionary={}
	var total_render:=0;var total_collision:=0;var total_surfaces:=0;var payload_bytes:=0
	var source_records:Array=doc.records.filter(func(r):return r.has("fortification"))
	Audit.demand(not source_records.is_empty(),"fortification records present",errors)
	var gltf:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path));var disk_refs:Dictionary={}
	for node:Dictionary in gltf.get("nodes",[]):
		for r:Dictionary in node.get("extras",{}).get("rmmo_records",[]):disk_refs[r.uuid]=r.get("rmmo_ref",{})
	for record:Dictionary in source_records:
		var row:Dictionary={"id":record.uuid,"part":record.fortification.part,"role":record.fortification.role,"collision":record.get("collision",""),"dynamic":record.has("fixture"),"payload":{},"materials":[],"geometry":[]}
		var data:Dictionary={}
		if record.has("house_prefab"):
			var payload:Dictionary=record.house_prefab;data=Frozen.decode(payload)
			Audit.demand(not data.is_empty(),record.uuid+" frozen checksum and structure",errors)
			if data.is_empty():rows.append(row);continue
			row.payload={"sha256":payload.sha256,"decoded_bytes":payload.length,"zstd_bytes":Marshalls.base64_to_raw(payload.data).size(),"generator":data.get("generator","")};payload_bytes+=payload.length
		elif record.has("fixture"):
			# Same native procedural path as WorldDocument, preserving fixture semantics.
			var node:MeshInstance3D=doc._mesh(record,false)
			row.native_generator="world_document._mesh(record,false) / building_fixtures.transform"
			Audit.demand(node!=null and node.mesh!=null and not node.has_meta("tile_error") and not node.has_meta("paint_error"),record.uuid+" native fixture geometry",errors)
			if node!=null and node.mesh!=null:
				var cache:Dictionary={};cache[[record.uuid]]={"mesh":node.mesh,"source":node.mesh}
				data=Frozen.Cook.pack(cache,"readonly fixture audit","native fixture")
				row.fixture_pose=str(node.transform);row.fixture=record.fixture.duplicate(true)
			if node!=null:node.free()
			Audit.demand(not data.get("entries",[]).is_empty(),record.uuid+" fixture CPU pack",errors)
			if data.get("entries",[]).is_empty():rows.append(row);continue
		else:
			row.unfrozen_reason="unfrozen generated component";pending.append({"id":record.uuid,"reason":row.unfrozen_reason})
			rows.append(row);continue
		var reference:Dictionary=disk_refs.get(record.uuid,{})
		if not reference.is_empty():
			row.native_resource=Audit.file_identity(path.get_base_dir().path_join(reference.uri))
			Audit.demand(row.native_resource.get("sha256","")==reference.sha256 and row.native_resource.get("bytes",0)==int(reference.length),record.uuid+" native resource SHA/bytes",errors)
		row.native_storage="rmmo_ref" if not reference.is_empty() else ("inline_payload" if record.has("house_prefab") else "native_dynamic_fixture")
		var local_materials:Dictionary={}
		var rendered:Array=[];var collided:Array=[];var active_slots:Dictionary={}
		for entry:Array in data.entries:
			rendered.append(entry[1][0]);collided.append(entry[1][1])
			var render_mesh:Dictionary=data.meshes[entry[1][0]]
			total_render+=Audit.mesh_triangles(render_mesh);total_collision+=Audit.mesh_triangles(data.meshes[entry[1][1]])
			total_surfaces+=1 if render_mesh.box_size!=Vector3.ZERO else render_mesh.surfaces.size()
			for slot:int in render_mesh.materials:active_slots[slot]=true
		for slot:int in active_slots:
			var value:Dictionary=data.materials[slot];var key:=City.token(value)
			if not materials.has(key):materials[key]=Audit.material_audit(value,images,errors,record.uuid)
			local_materials[slot]=materials[key];row.materials.append(key)
		row.serialized_material_slots=data.materials.size();row.active_material_slots=active_slots.keys()
		for mi in data.meshes.size():
			var mesh:Dictionary=data.meshes[mi];var key:=str(mesh.box_size)+":"+Cpu.geometry_signature(mesh.surfaces,mesh.get("lods",[]))
			var row_mesh:Dictionary={"index":mi,"key":key,"base_triangles":Audit.mesh_triangles(mesh),"cpu_channel_bytes":0,"lod_index_bytes":0,"lods":[],"surfaces":[],"rendered":mi in rendered,"collision":mi in collided}
			for si in mesh.surfaces.size():
				var material:Dictionary=local_materials.get(mesh.materials[si],{})
				var surface:=Audit.surface_audit(mesh.surfaces[si],mi in rendered and material.get("normal_enabled",false),false,0.)
				surface.surface_index=si;surface.material_slot=mesh.materials[si];row_mesh.surfaces.append(surface)
				row_mesh.cpu_channel_bytes+=surface.cpu_channel_bytes
				if mi in rendered:Audit.demand(surface.attribute_check_passed,record.uuid+" UV/normal/tangent "+str([mi,si]),errors)
			if mesh.box_size!=Vector3.ZERO:
				var box:=BoxMesh.new();box.size=mesh.box_size
				var surface:=Audit.surface_audit(box.get_mesh_arrays(),false,false,0.)
				surface.procedural_source="native BoxMesh";row_mesh.surfaces.append(surface)
				row_mesh.cpu_channel_bytes+=surface.cpu_channel_bytes
				if mi in rendered:Audit.demand(surface.attribute_check_passed,record.uuid+" generated BoxMesh attributes",errors)
			for levels:Dictionary in mesh.get("lods",[]):
				var lods:Array=[]
				for threshold in levels:
					lods.append({"screen_error":threshold,"triangles":levels[threshold].size()/3});row_mesh.lod_index_bytes+=levels[threshold].size()*4
				row_mesh.lods.append(lods)
			unique[key]=row_mesh;row.geometry.append(row_mesh)
		rows.append(row)
	var encoded:=0;var decoded:=0;var mips:=0;var texture_shas:Dictionary={};var channel_bytes:=0;var lod_bytes:=0;var lod_meshes:=0
	for texture:Dictionary in images.values():
		if not texture.get("decoded",false):continue
		if texture_shas.has(texture.get("sha256","")):continue
		texture_shas[texture.get("sha256","")]=true;encoded+=texture.get("bytes",0);decoded+=texture.get("decoded_bytes",0);mips+=texture.get("rgba8_or_native_mips_conservative_bytes",0)
	for mesh:Dictionary in unique.values():
		channel_bytes+=mesh.cpu_channel_bytes;lod_bytes+=mesh.lod_index_bytes
		if mesh.lod_index_bytes>0:lod_meshes+=1
	Audit.demand(FileAccess.get_sha256(path)==hash_before,"readonly source unchanged",errors)
	var report:Dictionary={"map":path,"map_sha256":hash_before,"rows":rows,"materials":materials,"textures":images,"errors":errors,"pending_unfrozen_records":pending,"passed":errors.is_empty() and pending.is_empty(),"scope":"new frozen native town fortifications; original module unchanged; no reduction applied", "totals":{"native_fortification_records":rows.size(),"expanded_render_base_triangles":total_render,"expanded_stored_collision_base_triangles":total_collision,"surface_instances_before_renderer_batching":total_surfaces,"expanded_native_payload_decoded_bytes":payload_bytes,"unique_geometry":unique.size(),"unique_cpu_channels_bytes":channel_bytes,"unique_lod_index_bytes":lod_bytes,"unique_meshes_with_lods":lod_meshes,"unique_texture_contents":texture_shas.size(),"encoded_texture_bytes":encoded,"decoded_texture_bytes":decoded,"texture_rgba8_or_native_mips_conservative_bytes":mips},"memory_note":"Decoded buffers and conservative mip budget; not measured process RSS or VRAM. Only render-referenced material slots contribute texture costs. Collision triangles describe stored meshes, not active physics instances. Compact boxes use native generated arrays. Runtime draw calls and batch statistics are separate.","acceptance":{"resource":"failed" if not errors.is_empty() else ("pending unfrozen fixture audit" if not pending.is_empty() else "passed"),"visual":"pending fixed near/middle/far/detail outdoor review","pipeline":"native checksum/decode/materials audited; undo/save/reopen in build receipt","integration":"candidate only until final publication"},"model_source":Audit.file_identity("D:/code/rmmo_runtime/packs/default/assets/fortifications/medieval_stone/medieval_wall.glb")}
	var f:=FileAccess.open(OUT+"/fortification_resource_audit.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print(JSON.stringify({"passed":report.passed,"totals":report.totals,"errors":errors}));quit(0 if report.passed else 1)
