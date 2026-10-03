extends RefCounted
## Document-local CPU-only save geometry. Never retain another set of GPU meshes.
const CpuMesh = preload("res://scripts/world3d/ground_cpu_mesh.gd")
const LIMIT_BYTES := 96 * 1024 * 1024
var entries: Dictionary = {}
var bytes := 0
var hits := 0
var misses := 0
var used: Dictionary = {}

func begin(records: Array) -> void:
	hits = 0; misses = 0
	used.clear()
	var ids := {}
	for record in records: ids[str(record.uuid)] = true
	for id in entries.keys():
		if not ids.has(id): remove(id)

func remove(id: String) -> void:
	if entries.has(id): bytes -= entries[id].bytes; entries.erase(id)

func key(record: Dictionary, context: Dictionary) -> String:
	if record.has("tile3d"): return "" # External model kits retain their ordinary build path.
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes([record, context.get("normals", {})]))
	return hash.finish().hex_encode()

func get_mesh(id: String, signature: String) -> Mesh:
	if signature.is_empty(): return null
	if not entries.has(id) or entries[id].key != signature:
		remove(id); misses += 1; return null
	var entry: Dictionary = entries[id]
	entries.erase(id); entries[id] = entry
	hits += 1
	used[id] = true
	# The export tree is off-screen. Export these arrays directly instead of
	# uploading another ArrayMesh and quantizing its packed normals a second time.
	return entry.mesh

func put_mesh(id: String, signature: String, source: Mesh) -> void:
	if signature.is_empty(): return
	var cpu = CpuMesh.capture(source)
	var cost := 0
	for surface in cpu.surfaces:
		for values in surface:
			if values != null: cost += values.to_byte_array().size()
	if cost > LIMIT_BYTES: return
	remove(id)
	# Pin entries used this build: sequential scans larger than the cache must not
	# evict every entry just before it can be reused on the following save.
	for candidate in entries.keys():
		if bytes + cost <= LIMIT_BYTES: break
		if not used.has(candidate): remove(candidate)
	if bytes + cost > LIMIT_BYTES: return
	entries[id] = {"key": signature, "mesh": cpu, "bytes": cost}
	used[id] = true
	bytes += cost
