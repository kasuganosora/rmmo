extends RefCounted
## Internal, process-local proof issued only after Index.read validates a fresh
## directory. This is a boundary against untrusted serialized data, not against
## hostile GDScript: project code is trusted and '_' is a naming convention.
## Never serialize this object or put it inside the index it owns (a ref cycle).
const MAX_DEPTH := 64
const MAX_VALUES := 2000000
var _index: Dictionary = {}
var _rows_by_uuid: Dictionary = {}
var _issuer: RefCounted
var _path := ""
var _root := ""
var _source_sha := ""
var _generator := ""
var _extras: Dictionary = {}
var _rows: Array = []
var _groups: Dictionary = {}
var _models: Dictionary = {}

## Trusted internal factory. A caller-created issuer cannot match Index's key.
## The read result must still be privately owned by the issuing load operation.
static func issue(index: Dictionary, path: String, root: String, issuer: RefCounted) -> RefCounted:
	if issuer == null or path.is_empty() or root.is_empty(): return null
	if not _seal(index, 0, [], [MAX_VALUES]): return null
	var result := new()
	result._index = index; result._path = path; result._root = root
	result._source_sha = index.source_sha256; result._generator = index.generator
	result._extras = index.extras; result._rows = index.rows; result._groups = index.groups; result._models = index.models
	for row: Dictionary in result._rows: result._rows_by_uuid[row.uuid] = row
	result._rows_by_uuid.make_read_only()
	result._issuer = issuer # Publish the issuer only after every container is sealed.
	return result

func matches(index: Dictionary, root: String, issuer: RefCounted, path: String = "") -> bool:
	if _issuer == null or not is_same(_issuer, issuer) or root != _root or (not path.is_empty() and path != _path): return false
	if not is_same(index, _index) or not index.is_read_only(): return false
	return index.source_sha256 == _source_sha and index.generator == _generator and is_same(index.extras, _extras) and is_same(index.rows, _rows) and is_same(index.groups, _groups) and is_same(index.models, _models)

func rows_by_uuid() -> Dictionary:
	return _rows_by_uuid

## Index rows use only math values and plain JSON containers. Packed arrays,
## Objects, Callables, Signals and RIDs are deliberately outside this contract.
## Only the current ancestor chain is compared by identity (bounded by depth),
## avoiding an O(N^2) global list of every visited container. Repeated aliases
## are harmless and consume the same finite traversal budget.
static func _seal(value: Variant, depth: int, ancestors: Array, budget: Array) -> bool:
	budget[0] -= 1
	if depth > MAX_DEPTH or budget[0] < 0: return false
	match typeof(value):
		TYPE_DICTIONARY, TYPE_ARRAY:
			for ancestor in ancestors:
				if is_same(ancestor, value): return false
			ancestors.append(value)
			if value is Dictionary:
				for key in value:
					if not (key is String or key is StringName) or not _seal(value[key], depth + 1, ancestors, budget): ancestors.pop_back(); return false
			else:
				for child in value:
					if not _seal(child, depth + 1, ancestors, budget): ancestors.pop_back(); return false
			ancestors.pop_back(); value.make_read_only(); return true
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_VECTOR2: return value.is_finite()
		TYPE_VECTOR3: return value.is_finite()
		TYPE_VECTOR2I, TYPE_VECTOR3I: return true
		TYPE_AABB: return value.position.is_finite() and value.size.is_finite()
	return false
