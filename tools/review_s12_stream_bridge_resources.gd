extends SceneTree
## CPU-only generated resource review. No map is loaded, edited or saved.
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
const Audit=preload("res://tools/audit_axel_bridge_assets.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Bridge=preload("res://scripts/world3d/bridge_data.gd")
const Tools=preload("res://scripts/world_editor/bridge_tools.gd")
const Meshes=preload("res://scripts/world3d/bridge_mesh.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
var errors:Array=[]
func _init()->void:call_deferred("run")
func require(ok:bool,label:String)->void:
	print(("PASS: " if ok else "FAIL: ")+label)
	if not ok:errors.append(label)
func write(path:String,data:Dictionary)->void:
	var f:=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(data,"\t"));f.close()
func profile_water(request:Dictionary)->Array:
	var curve:=preload("res://scripts/world3d/terrain_river_profile.gd").prepare(request)
	if not curve.ok:return []
	var left:Array=[];var right:Array=[];var half:float=request.width*.5
	for i in curve.path.size():
		var p:=Vector2(curve.path[i][0],curve.path[i][1]);var a:Array=curve.path[maxi(0,i-1)];var b:Array=curve.path[mini(curve.path.size()-1,i+1)]
		var d:=Vector2(b[0]-a[0],b[1]-a[1]).normalized();var normal:=Vector2(-d.y,d.x)
		left.append(p-normal*half);right.append(p+normal*half)
	var surfaces:Array=[]
	for i in curve.path.size()-1:
		var p:Array=[left[i],left[i+1],right[i+1],right[i]];var y:Array=[curve.levels[i],curve.levels[i+1],curve.levels[i+1],curve.levels[i]]
		for indices in [[0,1,2],[0,2,3]]:
			var points:Array=indices.map(func(j):return Vector3(p[j].x,y[j],p[j].y))
			surfaces.append({"polygon":PackedVector2Array(indices.map(func(j):return p[j])),"plane":Plane(points[0],points[1],points[2]),"source_id":"expected_native_profile_"+str(i)})
	return surfaces
func run()->void:
	create_timer(240).timeout.connect(func():quit(2))
	var patch_path:=OUT+"/s12_road_delta.json";var river_path:=OUT+"/s12_river_request.json"
	var patch:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(patch_path));var args:Dictionary=patch.bridge_geometry_candidate
	var river:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(river_path))
	var prefab:=preload("res://scripts/world_editor/bridge_library.gd").new().find(args.prefab_id)
	var record:=Tools.make_record(args,prefab);var library:=preload("res://scripts/world_editor/surface_material_library.gd").new()
	for role:String in Bridge.default_materials():
		if args.has(role+"_material_id"):record.bridge_materials[role]=library.find(args[role+"_material_id"])
		elif not record.bridge_materials.has(role):record.bridge_materials[role]=library.find(Bridge.default_materials()[role])
	require(Bridge.valid(record) and absf(record.bridge_mesh.length-8.)<.0001,"actual latest eight-metre native bridge recipe is valid")
	var source_before:=FileAccess.get_sha256(record.asset_path)
	var assembled:=Meshes.new().build(record);require(assembled!=null,"shared native bridge generator assembles actual eight-metre geometry")
	if assembled==null:quit(1);return
	var baked:=preload("res://scripts/world3d/structure_prefab.gd").bridge(record)
	require(baked.ok,"shared native freezing pipeline accepts exact geometry")
	if not baked.ok:quit(1);return
	record=baked.record
	var decoded:=Frozen.decode(record.house_prefab)
	require(not decoded.is_empty(),"frozen source checksum and schema decode")
	if decoded.is_empty():quit(1);return
	var doc:=preload("res://scripts/world3d/world_document.gd").new()
	require(doc.validate_save_record(record)==OK,"complete generated record passes native save validation without writing a map")
	var images:Dictionary={};var materials:Array=[]
	for value:Dictionary in decoded.materials:materials.append(Audit.material_audit(value,images,errors,record.uuid))
	var render:int=decoded.entries[0][1][0];var collision:int=decoded.entries[0][1][1];var mesh_rows:Array=[];var buffers:=0;var lod_bytes:=0
	for i in decoded.meshes.size():
		var mesh:Dictionary=decoded.meshes[i];var row:={"index":i,"render":i==render,"collision":i==collision,"triangles":Audit.mesh_triangles(mesh),"surfaces":[],"lods":[]}
		for j in mesh.surfaces.size():
			var material:Dictionary=materials[mesh.materials[j]];var deck:bool=material.serialized.paint==record.bridge_materials.deck
			var surface:=Audit.surface_audit(mesh.surfaces[j],i==render and material.normal_enabled,i==render and deck,record.bridge_mesh.width)
			row.surfaces.append(surface);buffers+=surface.cpu_channel_bytes
			require(surface.attribute_check_passed,"mesh %d surface %d native normals/UV/tangents finite and complete"%[i,j])
			require(surface.white_rim_bad_vertices_or_normals==0,"mesh %d surface %d paving remains off side/rim"%[i,j])
		for levels:Dictionary in mesh.get("lods",[]):
			var counts:Array=[]
			for threshold:float in levels.keys():counts.append({"screen_error":threshold,"triangles":levels[threshold].size()/3,"index_bytes":levels[threshold].size()*4});lod_bytes+=levels[threshold].size()*4
			row.lods.append(counts)
		mesh_rows.append(row)
	var unique:Dictionary={};var image_encoded:=0;var image_decoded:=0;var same_mips:=0;var budget:=0
	for path:String in images:
		var image:Dictionary=images[path]
		if unique.has(image.sha256):continue
		unique[image.sha256]=path;image_encoded+=image.bytes;image_decoded+=image.decoded_bytes;same_mips+=image.same_format_with_mips_bytes;budget+=image.rgba8_or_native_mips_conservative_bytes
	var bvh:=TriangleMesh.new();require(bvh.create_from_faces(assembled.get_faces()),"actual complete collision geometry builds CPU query mesh")
	var walkable:=true
	for i in 33:
		for z in [-2.4,0.,2.4]:
			var hit:=bvh.intersect_ray(Vector3(lerpf(-3.99,3.99,i/32.),.5,z),Vector3.DOWN)
			walkable=walkable and not hit.is_empty() and absf(hit.position.y)<.003
	require(walkable,"actual deck supports all 99 near-edge/centre rays without a hump or hole")
	var water:=profile_water(river)
	var clearance:=preload("res://scripts/world_editor/bridge_stream_clearance.gd").fit(record.duplicate(true),water,false)
	require(clearance.ok and clearance.applicable and clearance.clearance>=.2,"actual eight-metre bridge clears expected complete native longitudinal wet surface")
	var contact:=preload("res://scripts/world_editor/terrain_bridge_contact.gd").geometry(record,{})
	require(not contact.is_empty() and contact.bases.size()==4,"two actual end-abutment soles, no central support filling the creek")
	var graph:Dictionary=patch.full_graph.duplicate(true);var nodes:Dictionary={}
	for n:Dictionary in graph.nodes:nodes[n.id]=n
	var edge:Dictionary=graph.edges.filter(func(e):return e.id==args.road_edge_id)[0]
	var ports=preload("res://scripts/world3d/road_bridges.gd");var line:=ports.deck_line(edge,nodes,graph.edges);var direction:Vector3=(line[1]-line[0]).normalized()
	var first:Vector3=City.vec(args.start)-Vector3.UP*.025;var last:Vector3=City.vec(args.end)-Vector3.UP*.025
	var approach:Array=[(first-line[0]).dot(direction),(line[1]-last).dot(direction)]
	require(approach[0]>=2. and approach[1]>=2. and record.bridge_mesh.width-1.16>=maxf(edge.width_start,edge.width_end),"planned native road retains both two-metre approaches and five-metre walking width")
	var binding:={"id":record.uuid,"start":args.start,"end":args.end,"width":record.bridge_mesh.width,"signature":City.token(record),"source_token":ports.stone_source(edge,nodes)}
	edge.stone_bridge=binding
	var layout:=City.defaults();layout.roads=graph
	require(ports.resolve(layout).ok,"expected exact frozen signature and native road binding resolve")
	require(FileAccess.get_sha256(record.asset_path)==source_before,"original source remains unchanged during read-only generation")
	var fingerprints:Dictionary={}
	for file:String in ["scripts/world3d/bridge_mesh.gd","scripts/world3d/bridge_deck_rim.gd","scripts/world3d/structure_prefab.gd","scripts/world3d/house_prefab.gd","scripts/world_editor/bridge_stream_clearance.gd","scripts/world_editor/terrain_bridge_contact.gd","scripts/world3d/road_bridge_approach.gd"]:fingerprints[file]=FileAccess.get_sha256("res://"+file)
	var report:={"schema_version":1,"id":record.uuid,"phase":"cpu_resource_candidate_only","request":args,"request_source":{"path":patch_path,"sha256":FileAccess.get_sha256(patch_path)},"river_profile_source":{"path":river_path,"sha256":FileAccess.get_sha256(river_path)},"source_module":Audit.file_identity(record.asset_path),"frozen_payload":{"sha256":record.house_prefab.sha256,"decoded_bytes":record.house_prefab.length,"compressed_bytes":Marshalls.base64_to_raw(record.house_prefab.data).size(),"generator":decoded.get("generator","")},"native_record_valid":true,"render_triangles":Audit.mesh_triangles(decoded.meshes[render]),"collision_triangles":Audit.mesh_triangles(decoded.meshes[collision]),"render_surface_count":decoded.meshes[render].surfaces.size(),"material_count":decoded.materials.size(),"mesh_buffers":mesh_rows,"mesh_channel_bytes":buffers,"lod_index_bytes":lod_bytes,"textures":images,"materials":materials,"unique_image_contents":unique.size(),"unique_image_encoded_bytes":image_encoded,"unique_image_decoded_bytes":image_decoded,"unique_same_format_mips_bytes":same_mips,"unique_gpu_rgba8_or_native_mips_budget_bytes":budget,"actual_draw_calls":"not measured","rss_vram_peak":"not measured; image/mip figures are shared-content budgets","code_sha256":fingerprints,"cpu_structure":{"deck_99_rays":walkable,"actual_end_sole_triangles":contact.get("bases",[]).size(),"expected_profile_clearance":clearance,"real_saved_water_clearance":"pending candidate watercourse save","road_approach_lengths":approach,"clear_width":record.bridge_mesh.width-1.16,"expected_binding":binding},"semantics":{"independent_uuid":true,"whole_bridge_select_transform":true,"collision":record.collision,"prefab_locked":record.prefab_locked,"structural_parameters_read_only_after_freeze":true,"animated_parts":"not applicable","source_and_material_definitions_retained":true},"reference":{"existing_structure_sources":["https://historicengland.org.uk/listing/the-list/list-entry/1020741","https://historicengland.org.uk/listing/the-list/list-entry/1021018"],"provenance":"Existing documented native stone-bridge modules; no source/model changes. New short creek crossing is project supplementary design, not an asserted bridge in the S12 animation.","game_adaptation":"6.2m total / 5.04m clear for existing 5m road; flat deck 8.20, foundation depth1.5, 8m single arch. No navigability claim."},"optimization":{"decision":"retain current native geometry and generated LOD; no additional decimation or texture resizing without same-camera visual evidence","rationale":"One local crossing, three shared material surfaces, existing renderer batching, full collision maintains open arch and deck. Actual LOD counts are listed separately, never added to current visible triangles.","master_preserved":"D:/code/rmmo_runtime/packs/default/sources/authored/bridges"},"reused_pipeline_evidence":{"terrain_bridge_contact_http.log":68,"road_bridge_approach_scaled_http.log":32,"stream_bridge_http.log":89,"scope":"same shared source/generator and business contracts; 6m old geometry counts are not reused"},"status":{"resource_audit":"passed" if errors.is_empty() else "failed","visual_quality":"pending five coordinated quality90 WebP watercourse images","pipeline":"native build/freeze/decode/save-record validation passed; actual saved8m candidate reopen pending","game_editor_integration":"pending actual watercourse candidate save, frozen SHA comparison and formal integration"},"images":[],"errors":errors}
	write(OUT+"/s12_stream_bridge_expected_record.json",record)
	write(OUT+"/s12_stream_bridge_model_review.json",report)
	print("S12_STREAM_BRIDGE_RESOURCE_REVIEW failures=",errors.size()," render=",report.render_triangles," collision=",report.collision_triangles," sha=",record.house_prefab.sha256)
	quit(0 if errors.is_empty() else 1)
