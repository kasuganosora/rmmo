extends RefCounted
## Small shared validator for persisted editor settings, independent of the UI/MCP.
## Boolean consumers need neither diagnostic paths nor one VM call per numeric
## component. Schemas are trusted program data; values retain the same checks as
## validate(). Keep validate() as the detailed error API for editor/MCP callers.
static func matches(value: Variant, schema: Dictionary) -> bool:
	match schema.get("type", ""):
		"object":
			if not value is Dictionary: return false
			for key in schema.get("required", []):
				if not value.has(key): return false
			var properties: Dictionary = schema.properties
			for key in value:
				if not properties.has(key) or not matches(value[key], properties[key]): return false
		"array":
			if not value is Array or value.size() < schema.get("minItems", 0) or value.size() > schema.get("maxItems", 256): return false
			var items: Dictionary = schema.items
			var kind: String = items.get("type", "")
			if kind == "number" or kind == "integer":
				var low: Variant = items.get("minimum", -INF); var high: Variant = items.get("maximum", INF)
				var integer: bool = kind == "integer"; var enumerated: bool = items.has("enum")
				for entry in value:
					if not (entry is int or entry is float) or not is_finite(float(entry)): return false
					if integer and entry != floorf(entry): return false
					if entry < low or entry > high or (enumerated and not items.enum.has(entry)): return false
			else:
				for entry in value:
					if not matches(entry, items): return false
		"string":
			if not value is String or value.length() > schema.get("maxLength", 2048): return false
		"boolean":
			if not value is bool: return false
		"number", "integer":
			if not (value is int or value is float) or not is_finite(float(value)): return false
			if schema.type == "integer" and value != floorf(value): return false
			if value < schema.get("minimum", -INF) or value > schema.get("maximum", INF): return false
	return not schema.has("enum") or schema.enum.has(value)

static func validate(value: Variant, schema: Dictionary, path: String = "settings") -> String:
	match schema.get("type", ""):
		"object":
			if not value is Dictionary: return path + " must be an object"
			for key in schema.get("required", []):
				if not value.has(key): return path + "." + key + " is required"
			for key in value:
				if not schema.properties.has(key): return path + "." + str(key) + " is not supported"
				var error := validate(value[key], schema.properties[key], path + "." + str(key))
				if not error.is_empty(): return error
		"array":
			if not value is Array or value.size() < schema.get("minItems", 0) or value.size() > schema.get("maxItems", 256): return path + " has invalid length"
			for entry in value:
				var error := validate(entry, schema.items, path)
				if not error.is_empty(): return error
		"string":
			if not value is String or value.length() > schema.get("maxLength", 2048): return path + " must be a bounded string"
		"boolean":
			if not value is bool: return path + " must be a boolean"
		"number", "integer":
			if not (value is int or value is float) or not is_finite(float(value)): return path + " must be finite"
			if schema.type == "integer" and value != floorf(value): return path + " must be an integer"
			if value < schema.get("minimum", -INF) or value > schema.get("maximum", INF): return path + " is out of range"
	if schema.has("enum") and not schema.enum.has(value): return path + " has an unsupported value"
	return ""

static func number(low: float, high: float, integer: bool = false) -> Dictionary:
	return {"type": "integer" if integer else "number", "minimum": low, "maximum": high}

static func vector(low: float, high: float) -> Dictionary:
	return {"type": "array", "items": number(low, high), "minItems": 3, "maxItems": 3}
