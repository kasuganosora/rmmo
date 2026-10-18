extends RefCounted
## Game and editor consume authored package references as authoritative.
## Explicit diagnostic readers can still audit bytes for regression comparisons.
## Serialized map data cannot change this process policy.
static var verify_packages:=false
static func trusted()->bool:return not verify_packages

## Imported package assets are named by their published SHA. Other paths need
## one content identity for derived cache invalidation; neither path requires a
## second complete source scan after the importer has read the same package.
static func source_identity(path:String,declared:String="")->String:
	if declared.length()==64 and declared.is_valid_hex_number(false):return declared
	var name:=path.get_file().get_basename()
	if name.length()==64 and name.is_valid_hex_number(false):return name
	return FileAccess.get_sha256(path)
