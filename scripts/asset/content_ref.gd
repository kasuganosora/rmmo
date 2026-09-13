extends RefCounted
## Parses content://{kind}/{id}[@{version}] references for AssetManager.

const SCHEME := "content://"

var kind: String = ""
var id: String = ""
var version: String = ""


static func parse(ref: String) -> RefCounted:
	var out = new()
	ref = ref.strip_edges()
	if ref.is_empty():
		return out
	var body := ref
	if body.begins_with(SCHEME):
		body = body.substr(SCHEME.length())
	elif body.begins_with("content:"):
		body = body.substr("content:".length()).lstrip("/")
	# kind/id@version
	var at := body.rfind("@")
	if at >= 0:
		out.version = body.substr(at + 1).strip_edges()
		body = body.substr(0, at)
	var slash := body.find("/")
	if slash < 0:
		out.kind = "asset"
		out.id = body.strip_edges()
		return out
	out.kind = body.substr(0, slash).strip_edges()
	out.id = body.substr(slash + 1).strip_edges()
	return out


static func make(p_kind: String, p_id: String, p_version: String = "") -> String:
	var s := "%s%s/%s" % [SCHEME, p_kind.strip_edges(), p_id.strip_edges()]
	if p_version.strip_edges() != "":
		s += "@%s" % p_version.strip_edges()
	return s


func is_valid() -> bool:
	return not kind.is_empty() and not id.is_empty()


func to_string_ref() -> String:
	var s := "%s%s/%s" % [SCHEME, kind, id]
	if version != "":
		s += "@%s" % version
	return s
