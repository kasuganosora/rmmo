extends "res://tools/place_medieval_town_houses.gd"
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
func run()->void:
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("result.json")))
	check(report.candidate_sha256==FileAccess.get_sha256(CANDIDATE),"candidate unchanged")
	var doc=Doc.open_file(CANDIDATE);check(doc!=null,"load fixed candidate")
	if failures:quit(1);return
	var converted:Dictionary={};var before:=0;var after:=0
	for r:Dictionary in doc.records:
		if not r.has("house_prefab"):continue
		var old:String=r.house_prefab.sha256
		if converted.has(old):r.house_prefab=converted[old];continue
		var data:=Frozen.decode(r.house_prefab).duplicate(true)
		var expected:Array=[]
		for value:Dictionary in data.meshes:
			var cpu:=Frozen.Cpu.new();cpu.surfaces=value.surfaces
			expected.append(cpu.get_faces())
		Frozen.compact_data(data)
		for i in data.meshes.size():
			var cpu:=Frozen.Cpu.new();cpu.surfaces=data.meshes[i].surfaces
			if cpu.get_faces()!=expected[i]:check(false,"indexing changed triangle sequence");quit(1);return
		var bytes:=var_to_bytes(data);before+=int(r.house_prefab.length);after+=bytes.size()
		r.house_prefab={"version":1,"sha256":Frozen.Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
		converted[old]=r.house_prefab
		if converted.size()%50==0:print("COMPACTED ",converted.size()," meshes, bytes ",before," -> ",after)
	# Geometry signatures cover immutable payloads, so update their native manifests.
	for instance:Dictionary in doc.map_meta.building_instances.values():
		for part:String in instance.parts:instance.signatures[part]=B.geometry_signature(doc._find(instance.parts[part]))
	for region:Dictionary in doc.map_meta.editor_layout.fortifications:
		for part:Dictionary in region.parts:part.signature=preload("res://scripts/world3d/city_layout.gd").token(doc._find(part.id))
	preload("res://scripts/world3d/structure_prefab.gd").refresh_bindings(doc.map_meta,doc.records)
	check(doc.validate_save()==OK,"compact payloads and ownership valid")
	if failures:quit(1);return
	check(doc.save(CANDIDATE)==OK,"atomic compact candidate save")
	var reopened=Doc.open_file(CANDIDATE);check(reopened!=null and equivalent(reopened.records,doc.records),"compact data reopens exactly")
	report.candidate_sha256=FileAccess.get_sha256(CANDIDATE);report.prefab_compaction={"unique_meshes":converted.size(),"before_bytes":before,"after_bytes":after,"all_triangles_exact":true};report.failures+=failures
	write_report("result.json",report);print("TOWN_COMPACT_FINISHED ",report.prefab_compaction," failures=",failures);quit(1 if failures else 0)
