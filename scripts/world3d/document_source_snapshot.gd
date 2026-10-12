extends RefCounted
## Internal worker result: JSON, digest and retained bytes all derive from one
## complete read. This object is never reconstructed from JSON/prepared flags.
## GDScript callers are trusted code; the public prepared Dictionary is NOT a
## capability to select this path. No scene/resource APIs are used here.
const RETAIN_LIMIT := 256 * 1024 * 1024
const COMPARE_CHUNK := 4 * 1024 * 1024
var _path := ""
var _signature := ""
var _data: Variant
var _bytes := PackedByteArray()
var _retained := false
var error := "Cannot read map source"

static func read_file(path: String, retain_limit: int = RETAIN_LIMIT) -> RefCounted:
	var result := new()
	result._path = path
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return result
	var size := file.get_length()
	var bytes := file.get_buffer(size)
	if bytes.size() != size or file.get_error() != OK: return result
	file.close()
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK: return result
	result._signature = context.finish().hex_encode()
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		result.error = "Invalid glTF document"
		return result
	result._data = parser.data
	# A limit only selects memory usage, never skips final verification.
	if size <= clampi(retain_limit, 0, RETAIN_LIMIT):
		result._bytes = bytes
		result._retained = true
	result.error = ""
	return result

func matches_disk() -> bool:
	if not error.is_empty() or _signature.length() != 64: return false
	if not _retained:
		var signature := FileAccess.get_sha256(_path)
		return signature.length() == 64 and signature == _signature
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null or file.get_length() != _bytes.size(): return false
	var offset := 0
	while offset < _bytes.size():
		var count := mini(COMPARE_CHUNK, _bytes.size()-offset)
		var current := file.get_buffer(count)
		if current.size() != count or file.get_error() != OK or current != _bytes.slice(offset, offset+count): return false
		offset += count
	# Like the previous SHA check this is a synchronous final observation, not
	# an OS writer lock. Never yield/call progress between this and publication.
	return file.get_length() == _bytes.size()
