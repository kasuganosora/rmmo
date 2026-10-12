extends RefCounted
## Optional CPU geometry work only. These facts never authorize publication or
## replace a source/dependency hash, physics receipt, or the normal ready gate.
static var enabled:=false # Candidate; shared by private preparation and adoption.
const NONE:=0
const AUTHORED:=1
const ALL:=2
const UNKNOWN:=-1
const MAX_CONSUMERS:=4096
const MAX_DEFINITIONS:=4096
const MAX_DEFINITION_BYTES:=4*1024*1024
const DESCRIPTOR_BYTES:=8192 # Conservative UTF-8 identity/container/copy allowance.

static func record_mode(record:Dictionary)->int:
	# A compact reference deliberately omits collision. Missing is not inheritance
	# until Store has hydrated and validated the definition.
	if record.has("rmmo_ref") or record.get("kind")!="asset":return UNKNOWN
	for field in ["house_prefab","bridge_mesh","tree_settings","banner","surface_paint"]:
		if record.has(field):return ALL # Generated/edited geometry retains its old preparation.
	var value:Variant=record.get("collision","")
	if not value is String:return ALL
	if value=="none":return NONE
	if value=="":return AUTHORED
	return ALL # walk/block and unknown values are conservative.

static func definition_key(compact:Dictionary)->String:
	var ref:Variant=compact.get("rmmo_ref")
	if not ref is Dictionary or not ref.get("uri") is String or not ref.get("sha256") is String:return ""
	if ref.uri.is_empty() or ref.uri.length()>1024 or ref.sha256.length()!=64:return ""
	for ch in ref.sha256:
		if ch not in "0123456789abcdef":return ""
	return ref.uri+"|"+ref.sha256

static func consumer(record:Dictionary,compact:Dictionary={})->Dictionary:
	return {"mode":record_mode(record),"definition":definition_key(compact if not compact.is_empty() else record)}

static func resolve(consumers:Array,prepared_records:Array=[],requests:Array=[],path:String="",known:Dictionary={})->Dictionary:
	# Learned values come only from this job's successful reference transaction.
	# URI+SHA is scoped to one map and source path by the owning queue. State/pose
	# overlays cannot override collision (it is not a Store.STATE_FIELDS member).
	var definitions:Dictionary={};var by_uuid:Dictionary={}
	if consumers.is_empty() or consumers.size()>MAX_CONSUMERS or requests.size()>MAX_CONSUMERS:return {"mode":ALL,"definitions":definitions}
	for request:Variant in requests:
		if not request is Dictionary:continue
		var compact:Variant=request.get("compact_record")
		if compact is Dictionary and compact.get("uuid") is String:
			by_uuid[compact.uuid]=definition_key(compact)
	for record:Variant in prepared_records:
		if not record is Dictionary or record.get("asset_path")!=path:continue
		var key:String=by_uuid.get(str(record.get("uuid","")),"")
		var mode:=record_mode(record)
		if not key.is_empty() and mode!=UNKNOWN and definitions.size()<MAX_DEFINITIONS:
			# Contradictory data can only increase preparation, never suppress it.
			definitions[key]=maxi(int(definitions.get(key,NONE)),mode)
	var required:=NONE
	for row:Variant in consumers:
		if not row is Dictionary:return {"mode":ALL,"definitions":definitions}
		var mode:Variant=row.get("mode",UNKNOWN)
		if not mode is int:return {"mode":ALL,"definitions":definitions}
		if mode==UNKNOWN:
			var key:Variant=row.get("definition","")
			mode=definitions.get(key,known.get(key,ALL)) if key is String and not key.is_empty() else ALL
		if not mode is int or mode not in [NONE,AUTHORED,ALL]:mode=ALL
		required=maxi(required,mode)
	return {"mode":required,"definitions":definitions}

static func needs_geometry(extras:Variant,mode:int)->bool:
	if mode==NONE:return false
	if mode!=AUTHORED or not extras is Dictionary:return true
	# Missing/invalid/unknown node policy keeps the former full preparation.
	return extras.get("rmmo_collision")!="none"

static func needs_adopted_collision(extras:Dictionary)->bool:
	# This sees the final per-instance namespace/override result. Render-only
	# geometry stays in spec.mesh and remains selectable in the editor.
	return not enabled or extras.get("rmmo_collision")!="none"
