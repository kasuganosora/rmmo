extends SceneTree
## CPU-only research prototype. Reads an EXISTING validated index, never builds
## one, imports a model, hydrates rmres, or writes a production cache/map.
## The integer directory is NOT a trusted replacement for Index.read: exact
## bounds, authored metadata and ownership/closure proofs remain in the index.
const Index = preload("res://scripts/world3d/map_dependency_index.gd")
const ROOT := "D:/code/rmmo_runtime"
const DEFAULT_MAP := ROOT + "/cache/world3d/reference_load_checkpoint_26004507/map.gltf"
const DEFAULT_OUT := ROOT + "/review_artifacts/dependency_manifest_20261009"
const LIMIT := 64 * 1024 * 1024
const HEADER := 112
const MAGIC := "RMDIAG01"
const REPEATS := 7
const QUERY_REPEATS := 31
const CHUNK := 32.0
const HALO := 8.0
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(bytes)
	return context.finish().hex_encode()

func stats(values: Array) -> Dictionary:
	var sorted := values.duplicate(); sorted.sort()
	return {"n": sorted.size(), "median_us": sorted[sorted.size()/2], "p95_us": sorted[mini(sorted.size()-1, ceili(sorted.size()*.95)-1)], "min_us": sorted[0], "max_us": sorted[-1]}

func timed(fn: Callable, repeats: int) -> Dictionary:
	var values: Array = []
	for i in repeats:
		var start := Time.get_ticks_usec(); var result: Variant = fn.call()
		values.append(Time.get_ticks_usec()-start)
		if result == null: check(false, "timed call returned null")
	return stats(values)

func portable(value: Variant) -> Variant:
	# JSON's numeric domain does not preserve Variant int versus float (nor every
	# 64-bit integer). Preserve the original integer type explicitly, not by
	# weakening equality or rounding decoded values to an expected schema.
	if value is int: return {"$gd":"int64","v":str(value)}
	if value is AABB: return {"$gd": "AABB", "v": [value.position.x, value.position.y, value.position.z, value.size.x, value.size.y, value.size.z]}
	if value is Vector2i: return {"$gd": "Vector2i", "v": [value.x, value.y]}
	if value is Vector3: return {"$gd": "Vector3", "v": [value.x, value.y, value.z]}
	if value is Dictionary:
		var out := {}
		for key in value: out[key] = portable(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item in value: out.append(portable(item))
		return out
	assert(typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING], "unsupported portable type")
	return value

func native(value: Variant) -> Variant:
	if value is Dictionary:
		if value.has("$gd"):
			var a: Variant = value.v
			match value["$gd"]:
				"int64": return int(a)
				"AABB": return AABB(Vector3(a[0],a[1],a[2]), Vector3(a[3],a[4],a[5]))
				"Vector2i": return Vector2i(a[0],a[1])
				"Vector3": return Vector3(a[0],a[1],a[2])
		var out := {}
		for key in value: out[key] = native(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item in value: out.append(native(item))
		return out
	return value

func first_difference(a: Variant, b: Variant, path: String = "root") -> String:
	if typeof(a)!=typeof(b): return "%s: type %s versus %s" % [path,type_string(typeof(a)),type_string(typeof(b))]
	if a is Dictionary:
		if a.size()!=b.size(): return path+": dictionary size"
		for key in a:
			if not b.has(key): return path+": missing "+str(key)
			var difference := first_difference(a[key],b[key],path+"."+str(key))
			if not difference.is_empty(): return difference
		return ""
	if a is Array:
		if a.size()!=b.size(): return path+": array size"
		for i in a.size():
			var difference := first_difference(a[i],b[i],path+"[%d]" % i)
			if not difference.is_empty(): return difference
		return ""
	return "" if a==b else "%s: %s versus %s" % [path,str(a),str(b)]

func json_bytes(value: Variant) -> PackedByteArray:
	return JSON.stringify(value, "", true, true).to_utf8_buffer()

func overlap(a: AABB, b: AABB) -> bool:
	return a.position.x <= b.end.x and a.end.x >= b.position.x and a.position.z <= b.end.z and a.end.z >= b.position.z

func zig(value: int) -> int: return value*2 if value >= 0 else -value*2-1
func unzig(value: int) -> int: return value/2 if value%2 == 0 else -(value+1)/2

func add_entity(cells: Dictionary, globals: Array, entity: int, bounds: AABB, eager: bool) -> void:
	var low := Vector2i(floori(bounds.position.x/CHUNK), floori(bounds.position.z/CHUNK))
	var high := Vector2i(floori(bounds.end.x/CHUNK), floori(bounds.end.z/CHUNK))
	# Large/unknown objects are conservative candidates, still exact-filtered.
	if eager or high.x-low.x > Index.MAX_CHUNK_SPAN or high.y-low.y > Index.MAX_CHUNK_SPAN:
		globals.append(entity); return
	for x in range(low.x,high.x+1):
		for z in range(low.y,high.y+1):
			var key := Vector2i(x,z)
			if not cells.has(key): cells[key] = []
			cells[key].append(entity)

func build_table(index: Dictionary) -> Dictionary:
	var table := {"version":1,"chunk_m":32,"halo":8,"row_count":index.rows.size(),"dependencies":[],"row_dependencies":[],"group_keys":index.groups.keys(),"group_spans":[],"group_members":[],"cells":[],"references":[],"globals":[]}
	var dep_ids := {}; var cells := {}
	for row: Dictionary in index.rows:
		var ref: Dictionary = row.reference
		if not dep_ids.has(ref.uri):
			dep_ids[ref.uri] = table.dependencies.size()
			table.dependencies.append({"uri":ref.uri,"sha256":ref.sha256,"length":ref.length})
		table.row_dependencies.append(dep_ids[ref.uri])
		if row.group_id.is_empty():
			var halo: float = maxf(HALO,row.terrain_halo) if row.terrain_halo > 0 else 0.0
			add_entity(cells,table.globals,row.order,row.bounds.grow(halo),row.classification=="global")
	for g in table.group_keys.size():
		var group: Dictionary = index.groups[table.group_keys[g]]
		table.group_spans.append([table.group_members.size(),group.members.size()]); table.group_members.append_array(group.members)
		add_entity(cells,table.globals,table.row_count+g,group.bounds,not group.bounds_known)
	var keys: Array = cells.keys(); keys.sort_custom(func(a: Vector2i,b: Vector2i)->bool: return a.x < b.x or (a.x==b.x and a.y<b.y))
	for key: Vector2i in keys:
		table.cells.append([zig(key.x),zig(key.y),table.references.size(),cells[key].size()]); table.references.append_array(cells[key])
	return table

func table_runtime(table: Dictionary) -> Dictionary:
	var cells := {}
	for cell: Array in table.cells: cells[Vector2i(unzig(int(cell[0])),unzig(int(cell[1])))] = [int(cell[2]),int(cell[3])]
	return {"table":table,"cells":cells}

func selected_result(ids: Array, table: Dictionary, candidates: int = -1) -> Dictionary:
	ids.sort(); var deps := {}
	for id in ids: deps[int(table.row_dependencies[int(id)])] = true
	var selected_deps: Array = deps.keys(); selected_deps.sort()
	return {"ids":ids,"dependency_ids":selected_deps,"candidates":candidates}

func source_sizes(paths: Dictionary) -> Dictionary:
	var bytes := 0; var missing: Array = []; var files: Array = []; var sorted: Array = paths.keys(); sorted.sort()
	for path: String in sorted:
		var file := FileAccess.open(path,FileAccess.READ)
		if file==null: missing.append(path)
		else:
			var length := file.get_length(); bytes+=length; file.close()
			files.append({"path":path,"bytes":length})
	return {"count":paths.size(),"source_bytes":bytes,"missing":missing,"paths":sorted,"files":files}

func selection_breakdown(index: Dictionary, ids: Array, clip: AABB) -> Dictionary:
	var counts := {"global":0,"group":0,"ordinary":0}; var models := {"global":{},"group":{},"ordinary":{}}
	var all_models := {}; var forced_global_models := {}; var otherwise_models := {}; var outside := 0; var unknown := 0
	var reasons := {}; var references := {}; var stored_bytes := 0
	for at in ids:
		var row: Dictionary = index.rows[at]
		var category := "group" if not row.group_id.is_empty() else ("global" if row.classification=="global" else "ordinary")
		counts[category]+=1
		if category=="global": reasons[row.reason]=int(reasons.get(row.reason,0))+1
		if not references.has(row.reference.uri):
			references[row.reference.uri]=true; stored_bytes+=int(row.reference.length)
		var halo: float = maxf(HALO,row.terrain_halo) if row.terrain_halo>0 else 0.0
		var forced: bool = category=="global" and (not row.bounds_known or not overlap(row.bounds,clip.grow(halo)))
		if forced: outside+=1
		if category=="global" and not row.bounds_known: unknown+=1
		if row.asset_path.is_empty(): continue
		models[category][row.asset_path]=true; all_models[row.asset_path]=true
		if forced: forced_global_models[row.asset_path]=true
		else: otherwise_models[row.asset_path]=true
	var only_global := {}; var only_forced := {}
	for path: String in models.global:
		if not models.group.has(path) and not models.ordinary.has(path): only_global[path]=true
	for path: String in forced_global_models:
		if not otherwise_models.has(path): only_forced[path]=true
	return {"record_counts":counts,"global_reason_counts":reasons,"selected_rmres_declared_stored_bytes":stored_bytes,"global_outside_or_unknown_records":outside,"global_unknown_bounds_records":unknown,"unique_model_sources":source_sizes(all_models),"by_category_model_sources":{"global":source_sizes(models.global),"group":source_sizes(models.group),"ordinary":source_sizes(models.ordinary)},"model_sources_exclusively_introduced_by_global":source_sizes(only_global),"model_sources_exclusively_introduced_by_outside_or_unknown_global":source_sizes(only_forced),"scope":"Direct indexed row.asset_path only; no rmres hydration or indirect dependency discovery. Source sizes use file length only, not reads or hashes; rmres lengths are declared compact metadata, not measured hydration bytes."}

func scan_select(index: Dictionary, table: Dictionary, clips: Array) -> Dictionary:
	var groups := {}; var ids: Array = []
	for key: String in index.groups:
		var group: Dictionary = index.groups[key]; var needed: bool = not group.bounds_known
		for clip: AABB in clips:
			if overlap(group.bounds,clip): needed = true; break
		if needed: groups[key] = true
	for row: Dictionary in index.rows:
		var grouped: bool = not row.group_id.is_empty()
		var needed: bool = groups.has(row.group_id) if grouped else row.classification=="global"
		if not grouped and not needed:
			var halo: float = maxf(HALO,row.terrain_halo) if row.terrain_halo>0 else 0.0
			for clip: AABB in clips:
				if overlap(row.bounds,clip.grow(halo)): needed=true; break
		if needed: ids.append(row.order)
	return selected_result(ids,table)

func table_select(index: Dictionary, runtime: Dictionary, clips: Array) -> Dictionary:
	var table: Dictionary = runtime.table; var candidates := {}; var ids := {}
	for id in table.globals: candidates[int(id)] = true
	for clip: AABB in clips:
		for x in range(floori(clip.position.x/CHUNK),floori(clip.end.x/CHUNK)+1):
			for z in range(floori(clip.position.z/CHUNK),floori(clip.end.z/CHUNK)+1):
				var span: Array = runtime.cells.get(Vector2i(x,z),[])
				if span.is_empty(): continue
				for at in range(span[0],span[0]+span[1]): candidates[int(table.references[at])] = true
	for id: int in candidates:
		if id >= table.row_count:
			var group: Dictionary = index.groups[table.group_keys[id-table.row_count]]; var needed: bool = not group.bounds_known
			for clip: AABB in clips:
				if overlap(group.bounds,clip): needed=true; break
			if needed:
				var span: Array = table.group_spans[id-table.row_count]
				for at in range(int(span[0]),int(span[0])+int(span[1])): ids[int(table.group_members[at])] = true
		else:
			var row: Dictionary = index.rows[id]; var needed: bool = row.classification=="global"
			var halo: float = maxf(HALO,row.terrain_halo) if row.terrain_halo>0 else 0.0
			for clip: AABB in clips:
				if needed or overlap(row.bounds,clip.grow(halo)): needed=true; break
			if needed: ids[id] = true
	return selected_result(ids.keys(),table,candidates.size())

func cell_queries(index: Dictionary, table: Dictionary, runtime: Dictionary) -> Array:
	var result: Array = []
	var cell := AABB(Vector3(320,-100000,160),Vector3(32,200000,32))
	for expansion in [0,8]:
		var clip := cell.grow(float(expansion)); var clips: Array = [clip]
		var expected := Index.select(index,clips,HALO); var scanned := scan_select(index,table,clips); var actual := table_select(index,runtime,clips)
		check(actual.ids==expected.record_indices and scanned.ids==expected.record_indices,"cell (10,5) + %dm exact selected records" % expansion)
		var deps := {}; var definitions: Array = []; var uuids: Array = []
		for id in actual.dependency_ids:
			var reference: Dictionary = table.dependencies[id]
			deps[reference.uri]=reference.sha256; definitions.append(reference)
		for id in actual.ids: uuids.append(index.rows[id].uuid)
		check(deps==expected.dependencies,"cell (10,5) + %dm exact dependency set" % expansion)
		result.append({"name":"cell_10_5" if expansion==0 else "cell_10_5_expanded_8m","cell":[10,5],"base_cell_xz":[320,160,352,192],"clip_xz":[clip.position.x,clip.position.z,clip.end.x,clip.end.z],"safety_expansion_m":expansion,"terrain_halo_m":HALO,"whole_building_groups":true,"global_semantics_unchanged":true,"is_neighbor_ring":false,"selected_records":actual.ids.size(),"selected_dependencies":actual.dependency_ids.size(),"selected_groups":expected.selected_groups.size(),"selected_group_ids":expected.selected_groups,"record_indices":actual.ids,"record_uuids":uuids,"dependencies":definitions,"candidate_entities":actual.candidates,"breakdown":selection_breakdown(index,actual.ids,clip),"index_select_full_outputs":timed(func():return Index.select(index,clips,HALO),QUERY_REPEATS),"full_scan_selected_sets_only":timed(func():return scan_select(index,table,clips),QUERY_REPEATS),"integer_directory_selected_sets_only":timed(func():return table_select(index,runtime,clips),QUERY_REPEATS)})
	return result

func integer(value: Variant, limit: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and value>=0 and value<limit

func valid_table(table: Dictionary) -> bool:
	if table.get("version")!=1 or table.get("chunk_m")!=32 or table.get("halo")!=8 or not integer(table.get("row_count"),1000000): return false
	for key in ["dependencies","row_dependencies","group_keys","group_spans","group_members","cells","references","globals"]:
		if not table.get(key) is Array or table[key].size()>2000000: return false
	var rows := int(table.row_count); var groups: int = table.group_keys.size(); var entity_count := rows+groups
	if table.row_dependencies.size()!=rows or table.group_spans.size()!=groups: return false
	for dep in table.dependencies:
		if not dep is Dictionary or not dep.get("uri") is String or not dep.get("sha256") is String or dep.sha256.length()!=64 or not integer(dep.get("length"),1<<32): return false
	for id in table.row_dependencies:
		if not integer(id,table.dependencies.size()): return false
	for key in table.group_keys:
		if not key is String: return false
	for id in table.references+table.globals:
		if not integer(id,entity_count): return false
	for id in table.group_members:
		if not integer(id,rows): return false
	var seen := {}
	for cell in table.cells:
		if not cell is Array or cell.size()!=4: return false
		for n in cell:
			if not integer(n,1<<32): return false
		if cell[2]+cell[3]>table.references.size(): return false
		var key := Vector2i(unzig(int(cell[0])),unzig(int(cell[1])))
		if seen.has(key): return false
		seen[key]=true
	for span in table.group_spans:
		if not span is Array or span.size()!=2 or not integer(span[0],2000001) or not integer(span[1],2000001) or span[0]+span[1]>table.group_members.size(): return false
	return true

func encode_le(table: Dictionary) -> PackedByteArray:
	var lexical := json_bytes({"dependencies":table.dependencies,"group_keys":table.group_keys})
	var words: Array = [table.row_count,table.group_keys.size(),table.cells.size(),table.references.size(),table.globals.size(),table.group_members.size(),lexical.size()]
	words.append_array(table.row_dependencies)
	for cell: Array in table.cells: words.append_array(cell)
	words.append_array(table.references); words.append_array(table.globals)
	for span: Array in table.group_spans: words.append_array(span)
	words.append_array(table.group_members)
	var bytes := PackedByteArray(); bytes.resize(words.size()*4)
	for i in words.size(): bytes.encode_u32(i*4,int(words[i]))
	bytes.append_array(lexical)
	return bytes

func decode_le(bytes: PackedByteArray, validate: bool = true) -> Dictionary:
	if bytes.size()<28 or bytes.size()>LIMIT: return {}
	var counts: Array = []
	for i in 7: counts.append(bytes.decode_u32(i*4))
	for n in counts:
		if n>LIMIT: return {}
	var word_count: int = 7+counts[0]+counts[1]*2+counts[2]*4+counts[3]+counts[4]+counts[5]
	if word_count*4+counts[6]!=bytes.size(): return {}
	var lexical: Variant = JSON.parse_string(bytes.slice(word_count*4).get_string_from_utf8())
	if not lexical is Dictionary: return {}
	var table := {"version":1,"chunk_m":32,"halo":8,"row_count":counts[0],"dependencies":lexical.get("dependencies"),"group_keys":lexical.get("group_keys"),"row_dependencies":[],"cells":[],"references":[],"globals":[],"group_spans":[],"group_members":[]}
	var at := 28
	for section in [["row_dependencies",counts[0],1],["cells",counts[2],4],["references",counts[3],1],["globals",counts[4],1],["group_spans",counts[1],2],["group_members",counts[5],1]]:
		for i in int(section[1]):
			if section[2]==1: table[section[0]].append(bytes.decode_u32(at)); at+=4
			else:
				var row: Array = []
				for j in int(section[2]): row.append(bytes.decode_u32(at)); at+=4
				table[section[0]].append(row)
	return table if not validate or valid_table(table) else {}

func envelope(payload: PackedByteArray, source: String, generator: String) -> PackedByteArray:
	var bytes := PackedByteArray(); bytes.resize(HEADER)
	var prefix := MAGIC.to_ascii_buffer()
	for i in 8: bytes[i]=prefix[i]
	bytes.encode_u32(8,1); bytes.encode_u32(12,payload.size())
	for entry in [[16,sha(payload)],[48,source],[80,generator]]:
		var digest: PackedByteArray = str(entry[1]).hex_decode()
		for i in 32: bytes[int(entry[0])+i]=digest[i]
	bytes.append_array(payload); return bytes

func read_envelope(bytes: PackedByteArray, source: String, generator: String) -> Dictionary:
	if bytes.size()<HEADER or bytes.size()>LIMIT or bytes.slice(0,8).get_string_from_ascii()!=MAGIC or bytes.decode_u32(8)!=1: return {}
	var length := bytes.decode_u32(12)
	if length+HEADER!=bytes.size() or bytes.slice(48,80).hex_encode()!=source or bytes.slice(80,112).hex_encode()!=generator: return {}
	var payload := bytes.slice(HEADER)
	if sha(payload)!=bytes.slice(16,48).hex_encode(): return {}
	return decode_le(payload)

func codec_report(name_: String, encode: Callable, decode: Callable, out_dir: String) -> Dictionary:
	var bytes: PackedByteArray = encode.call(); var decoded: Variant = decode.call(bytes)
	check(decoded!=null, name_+" decode succeeds")
	var report := {"bytes":bytes.size(),"encode":timed(encode,REPEATS),"decode":timed(func(): return decode.call(bytes),REPEATS),"sha256":timed(func(): return sha(bytes),REPEATS),"compression":{}}
	FileAccess.open(out_dir.path_join(name_+".bin"),FileAccess.WRITE).store_buffer(bytes)
	for mode in [["zstd",FileAccess.COMPRESSION_ZSTD],["fastlz",FileAccess.COMPRESSION_FASTLZ]]:
		var compressed := bytes.compress(mode[1]); check(compressed.decompress(bytes.size(),mode[1])==bytes,name_+" "+mode[0]+" byte-exact round trip")
		report.compression[mode[0]] = {"bytes":compressed.size(),"ratio":float(compressed.size())/bytes.size(),"compress":timed(func():return bytes.compress(mode[1]),REPEATS),"decompress":timed(func():return compressed.decompress(bytes.size(),mode[1]),REPEATS)}
		FileAccess.open(out_dir.path_join(name_+"."+mode[0]),FileAccess.WRITE).store_buffer(compressed)
	return report

func run() -> void:
	var map_path := DEFAULT_MAP; var out_dir := DEFAULT_OUT
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()-1):
		if args[i]=="--map": map_path=args[i+1]
		if args[i]=="--output": out_dir=args[i+1]
	# Output is deliberately separate from all maps/packs/production caches.
	if not out_dir.replace("\\","/").simplify_path().begins_with(ROOT+"/review_artifacts/"):
		push_error("Output must remain within runtime/review_artifacts"); quit(1); return
	var started := Time.get_ticks_usec(); var index := Index.read(map_path,ROOT)
	var production_read_us := Time.get_ticks_usec()-started
	if not index.get("ok",false): print("Existing index rejected; no rebuild attempted: ",index); quit(1); return
	var cache_before := FileAccess.get_sha256(index.index_path)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var payload := {"version":Index.VERSION,"source_sha256":index.source_sha256,"generator":index.generator,"rows":index.rows,"models":index.models,"groups":index.groups}
	started=Time.get_ticks_usec(); var table := build_table(index); var build_us := Time.get_ticks_usec()-started
	check(valid_table(table),"integer directory has bounded valid spans and IDs")
	var runtime := table_runtime(table)
	if "--cells-only" in args:
		var cell_report := {"map":map_path,"index_path":index.index_path,"source_sha256":index.source_sha256,"generator":index.generator,"trusted_production_index_read_us_single_sample":production_read_us,"queries":cell_queries(index,table,runtime),"notes":["Exact current cell is x320..352,z160..192; this is not a 32 m radius around the player.","Expanded case grows this cell by 8 m to x312..360,z152..200. It is not a one-chunk neighbor ring.","Both cases preserve production terrain_halo=8 and all global/whole-building selection. Terrain-specific halo is additional to the expanded query where applicable.","Direct row.asset_path source bytes and declared rmres lengths only; indirect prefab/material/texture dependencies are not hydrated or measured.","Prototype is not a trusted production index or selected closure proof."]}
		cell_report.source_unchanged=FileAccess.get_sha256(map_path)==index.source_sha256; cell_report.index_unchanged=FileAccess.get_sha256(index.index_path)==cache_before
		check(cell_report.source_unchanged and cell_report.index_unchanged,"cell-only diagnostic preserves map and index bytes")
		cell_report.checks=checks; cell_report.failures=failures; cell_report.ok=failures.is_empty()
		FileAccess.open(out_dir.path_join("cell_report.json"),FileAccess.WRITE).store_string(JSON.stringify(cell_report,"\t",true,true))
		print(JSON.stringify({"ok":cell_report.ok,"checks":checks,"failures":failures,"report":out_dir.path_join("cell_report.json")}))
		quit(0 if cell_report.ok else 1); return
	var le := encode_le(table); var loaded := decode_le(le)
	check(loaded==table,"LE uint32 directory plus lexical dictionary round trips exactly")
	var portable_full: Variant = portable(payload)
	var json_full: Variant = native(JSON.parse_string(json_bytes(portable_full).get_string_from_utf8()))
	var json_difference := first_difference(payload,json_full)
	check(json_difference.is_empty(),"full index JSON retains exact native types and values: "+json_difference)
	var report := {"map":map_path,"index_path":index.index_path,"source_sha256":index.source_sha256,"generator":index.generator,"trusted_production_index_read_us_single_sample":production_read_us,"original_index_bytes":FileAccess.get_file_as_bytes(index.index_path).size(),"records":index.rows.size(),"groups":index.groups.size(),"model_descriptors":index.models.size(),"point":[321.2,160.3],"chunk_m":CHUNK,"terrain_halo":HALO,"table_build_us_single_sample":build_us,"directory":{"cells":table.cells.size(),"entity_references":table.references.size(),"global_candidate_entities":table.globals.size(),"unique_dependencies":table.dependencies.size(),"numeric_bytes":le.size()-json_bytes({"dependencies":table.dependencies,"group_keys":table.group_keys}).size(),"lexical_bytes":json_bytes({"dependencies":table.dependencies,"group_keys":table.group_keys}).size()},"codecs":{},"queries":[],"notes":["Diagnostic only: compact table is an acceleration structure, not a trusted index or closure proof.","The full validated index remains the exact-bounds/metadata/ownership side table; its bytes and validation must not be omitted from production total cost.","Production read is one measured validated read; repeated codec operations are warm in-memory serialization, not file I/O or source/model/rmres validation.","Full JSON tags native AABB/Vector2i types and includes reconstruction in decode; portable conversion measured separately.","Integer table query supports fixed 8 m terrain halo and 32 m cells; other halo policies require a rebuilt table or broader query.","Queries return selected record/dependency sets only; full Index.select also allocates deferred records/entries and extras.","No model or rmres hydration, geometry generation, GPU upload, scene publication, navigation or drawing is measured here."]}
	report.portable_conversion = timed(func():return portable(payload),REPEATS)
	report.full_json_semantic_difference = json_difference
	report.notes.append("Full JSON has explicit int64 annotations as well as native geometry tags; plain JSON numbers would erase Variant integer versus float semantics. This research codec is separate from the existing binary production format.")
	report.notes.append("Direct row.asset_path counts do not include indirect model, prefab, material or texture dependencies. A zero global-only direct GLB count does not mean global/native objects are free of resource work.")
	report.runtime_directory_construction = timed(func():return table_runtime(table),REPEATS)
	report.codecs.full_variant = codec_report("full_variant",func():return var_to_bytes(payload),func(b):return bytes_to_var(b),out_dir)
	report.codecs.full_json = codec_report("full_json",func():return json_bytes(portable_full),func(b):return native(JSON.parse_string(b.get_string_from_utf8())),out_dir)
	report.codecs.table_variant = codec_report("table_variant",func():return var_to_bytes(table),func(b):return bytes_to_var(b),out_dir)
	report.codecs.table_json = codec_report("table_json",func():return json_bytes(table),func(b):return JSON.parse_string(b.get_string_from_utf8()),out_dir)
	report.codecs.table_le_uint32 = codec_report("table_le_uint32",func():return encode_le(table),func(b):return decode_le(b,false),out_dir)
	report.table_structural_validation = timed(func():return valid_table(table),REPEATS)
	report.table_le_decode_including_structural_validation = timed(func():return decode_le(le,true),REPEATS)
	report.notes.append("All codec decode timings exclude common table schema validation. LE decode retains required section-length safety; common validation and LE validated decode are reported separately.")
	report.notes.append("The integer-only JSON table intentionally uses JSON numbers; all ID/span values are bounded uint32 and remain exact in doubles. It is semantically equivalent after checked integer conversion, not a Variant-type-identical representation.")
	report.cell_queries=cell_queries(index,table,runtime)
	# Check every wire form's lookup, not merely its serializer's return value.
	var decoded_tables := [bytes_to_var(var_to_bytes(table)),JSON.parse_string(json_bytes(table).get_string_from_utf8()),loaded]
	for radius in [32,64,96]:
		var clip := AABB(Vector3(321.2-radius,-100000,160.3-radius),Vector3(radius*2,200000,radius*2)); var clips: Array = [clip]
		var expected := Index.select(index,clips,HALO); var narrow := scan_select(index,table,clips); var actual := table_select(index,runtime,clips)
		check(actual.ids==expected.record_indices and narrow.ids==expected.record_indices,"radius %d record set equals Index.select" % radius)
		var deps := {}
		for id in actual.dependency_ids: deps[table.dependencies[id].uri]=table.dependencies[id].sha256
		check(deps==expected.dependencies,"radius %d dependency closure equals Index.select" % radius)
		for decoded: Dictionary in decoded_tables: check(table_select(index,table_runtime(decoded),clips).ids==expected.record_indices,"radius %d decoded wire form lookup matches" % radius)
		report.queries.append({"radius_m":radius,"selected_records":actual.ids.size(),"selected_dependencies":actual.dependency_ids.size(),"selected_groups":expected.selected_groups.size(),"candidate_entities":actual.candidates,"full_scan_entities":index.rows.size()+index.groups.size(),"breakdown":selection_breakdown(index,actual.ids,clip),"index_select_full_outputs":timed(func():return Index.select(index,clips,HALO),QUERY_REPEATS),"full_scan_selected_sets_only":timed(func():return scan_select(index,table,clips),QUERY_REPEATS),"integer_directory_selected_sets_only":timed(func():return table_select(index,runtime,clips),QUERY_REPEATS)})
	# Inclusive chunk boundaries, empty demand, zero extent, and two disjoint pins.
	var special: Array = [[],[AABB(Vector3(320,-1,160),Vector3(0,2,0))],[AABB(Vector3(288,-1,128),Vector3(32,2,32))],[AABB(Vector3(-32,-1,-32),Vector3(32,2,32))],[AABB(Vector3(300,-1,140),Vector3(32,2,32)),AABB(Vector3(-160,-1,0),Vector3(32,2,32))]]
	for clips: Array in special: check(table_select(index,runtime,clips).ids==Index.select(index,clips,HALO).record_indices,"boundary/empty/disjoint demand matches production")
	var wrapped := envelope(le,index.source_sha256,index.generator)
	check(not read_envelope(wrapped,index.source_sha256,index.generator).is_empty(),"bounded SHA envelope accepts prototype")
	check(read_envelope(wrapped,"0".repeat(64),index.generator).is_empty(),"changed expected source identity rejected")
	check(read_envelope(wrapped,index.source_sha256,"0".repeat(64)).is_empty(),"changed generator identity rejected")
	var corrupt := wrapped.duplicate(); corrupt[-1]^=1
	check(read_envelope(corrupt,index.source_sha256,index.generator).is_empty(),"payload corruption rejected before table decode")
	check(read_envelope(wrapped.slice(0,-1),index.source_sha256,index.generator).is_empty(),"truncated envelope rejected")
	var invalid := table.duplicate(true); invalid.cells[0][2]=invalid.references.size()+1
	check(read_envelope(envelope(encode_le(invalid),index.source_sha256,index.generator),index.source_sha256,index.generator).is_empty(),"rehashed out-of-range span rejected")
	invalid=table.duplicate(true); invalid.row_dependencies[0]=invalid.dependencies.size()
	check(read_envelope(envelope(encode_le(invalid),index.source_sha256,index.generator),index.source_sha256,index.generator).is_empty(),"rehashed out-of-range dependency rejected")
	FileAccess.open(out_dir.path_join("prototype_envelope.bin"),FileAccess.WRITE).store_buffer(wrapped)
	report.prototype_envelope_read = timed(func():return read_envelope(wrapped,index.source_sha256,index.generator),REPEATS)
	report.source_unchanged=FileAccess.get_sha256(map_path)==index.source_sha256
	report.index_unchanged=FileAccess.get_sha256(index.index_path)==cache_before
	check(report.source_unchanged and report.index_unchanged,"author map and production index unchanged")
	report.validation_boundary = ["Expected source SHA must itself come from a current full map snapshot, never mtime or this envelope.","Replacing a source/model/rmres after directory lookup still requires existing preparation before/after SHA and publication identity checks.","Envelope digest is corruption detection, not authentication; a rehashed semantically wrong but in-range table needs trusted rebuilding or equivalence validation.","Prototype structural checks do not verify path roots, model bounds freshness, ownership, shared-definition contents or complete selected closure.","Production Index.read still checks full source schema/closure/ownership/model bounds and can conservatively globalize changed model rows; table must be built after that normalization."]
	report.prototype_trusted_for_loading=false; report.selected_closure_verified=false
	report.checks=checks; report.failures=failures; report.ok=failures.is_empty()
	FileAccess.open(out_dir.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print(JSON.stringify({"ok":report.ok,"checks":checks,"failures":failures,"report":out_dir.path_join("report.json"),"production_read_us":production_read_us}))
	quit(0 if report.ok else 1)
