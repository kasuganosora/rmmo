extends RefCounted
## Resource versions save bandwidth without sharing permission-dependent data
## between characters. A response is applied atomically in capture order.
const RESOURCES=["combat-state","inventory","attributes","progression","entities","skills","statuses","areas","party","alliance","rewards","resurrection","interactions"]
var supported:=0 # unknown / supported / legacy (-1)
var scope:Dictionary={}
var revision:=0
var versions:Dictionary={}
var snapshots:Dictionary={}
var retry_scope:Dictionary={}
var retry_at:=0

func clear()->void:
	supported=0;scope.clear();revision=0;versions.clear();snapshots.clear();retry_scope.clear();retry_at=0

func known(context:Dictionary)->Dictionary:
	if scope!=context:
		scope=context.duplicate(true);revision=0;versions.clear();snapshots.clear()
	return versions.duplicate()

func _integer(value:Variant)->int:
	if value is String:
		if not value.is_valid_int():return -1
		var parsed:=int(value)
		return parsed if str(parsed)==value and parsed>=0 and parsed<=9007199254740991 else -1
	if value is int:return value if value>=0 and value<=9007199254740991 else -1
	if value is float and is_finite(value) and value>=0 and value<=9007199254740991 and value==floor(value):return int(value)
	return -1

func _context(value:Variant)->Dictionary:
	if not value is Dictionary:return {}
	return {"boot_id":value.get("boot_id",""),"session_epoch":_integer(value.get("session_epoch")),"map_generation":_integer(value.get("map_generation",0)),"map_ref":value.get("map_ref","")}

func _version(value:Variant)->bool:
	if not value is String or value.length()!=64:return false
	for c in value:
		if not c in "0123456789abcdef":return false
	return true

func apply(body:Dictionary,context:Dictionary)->Dictionary:
	if body.get("schema")!=1 or not body.get("ok",false) or _context(body.get("world_context"))!=context or scope!=context:return {"ok":false,"error":"stale_gameplay_snapshot"}
	var incoming:=_integer(body.get("revision"))
	if incoming<=0:return {"ok":false,"error":"invalid_snapshot_revision"}
	if incoming<=revision:return {"ok":true,"ignored":true,"revision":revision,"changed":[],"snapshots":snapshots.duplicate(true)}
	var resources:Variant=body.get("resources")
	var game_time:=_integer(body.get("game_time_us"))
	var elapsed:Variant=body.get("server_elapsed")
	if not resources is Dictionary or resources.size()!=RESOURCES.size() or game_time<0 or not (elapsed is float or elapsed is int) or not is_finite(float(elapsed)) or float(elapsed)<0:return {"ok":false,"error":"invalid_gameplay_snapshot"}
	var next:=snapshots.duplicate(true);var next_versions:Dictionary={};var changed:Array=[]
	for name:String in RESOURCES:
		var resource:Variant=resources.get(name)
		if not resource is Dictionary or not _version(resource.get("version")):return {"ok":false,"error":"invalid_snapshot_resource"}
		var version:String=resource.version
		if resource.has("data"):
			var value:Variant=resource.data
			if name=="entities" and not value is Array or name!="entities" and not value is Dictionary:return {"ok":false,"error":"invalid_snapshot_resource"}
			next[name]=value.duplicate(true);changed.append(name)
		elif not next.has(name) or versions.get(name)!=version:
			# Another in-flight response may have replaced the conditional base.
			# Keep the complete current projection and request a full batch.
			return {"ok":false,"need_full":true,"error":"snapshot_base_missing"}
		next_versions[name]=version
	next["combat-state"].server_elapsed=float(elapsed)
	next.statuses.game_time_us=game_time;next.areas.game_time_us=game_time
	versions=next_versions;snapshots=next;revision=incoming;supported=1
	return {"ok":true,"revision":revision,"changed":changed,"snapshots":snapshots.duplicate(true)}
