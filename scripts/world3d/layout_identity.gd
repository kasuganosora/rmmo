extends RefCounted
## Stable authored layout signatures. Keep this dependency-free so geometry
## and bridge metadata do not preload the layout authoring/validation graph.
static func canonical(value: Variant) -> Variant:
	# Integer microunits make JSON roundtrips stable without trusting float spelling.
	if value is float or value is int: return "number:"+str(roundi(float(value)*1000000))
	if value is Array: return value.map(func(item):return canonical(item))
	if value is Dictionary:
		var result:={}
		for key in value: result[key]=canonical(value[key])
		return result
	return value
static func token(graph: Variant) -> String:
	return JSON.stringify(canonical(graph)).sha256_text()

