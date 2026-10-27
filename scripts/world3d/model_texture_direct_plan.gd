extends RefCounted
## Caller MUST ensure direct-safe private native
## ownership through worker completion and main-thread commit/discard. The
## original scene and native PackedScene owner remain alive throughout.
const Cache=preload("res://scripts/world3d/model_texture_cache.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const MAX_MATERIALS:=4096
const MAX_USES:=8192
# Scheduling estimate only: 4 MiB fixed + 512 bytes per maximum material and
# use, rounded up. It is not an allocator/RSS measurement or proved upper bound.
# Admit alongside (not instead of) the existing full job peak/owner reservation.
const EXTRA_RESERVATION_BYTES:=12*1024*1024

static func _cancelled(token:RefCounted)->bool:
	return token!=null and token.is_cancelled()

static func prepare(scene:Node,token:RefCounted=null,use_limit:int=MAX_USES,material_limit:int=MAX_MATERIALS)->Dictionary:
	# Deliberately no writes to materials, the pool or renderer; no sync here.
	# Partial plan remains owned by the returned packet on every early exit.
	var plan:Dictionary={"state":"preparing","materials":[],"originals":[],"keys":[],"material_index":[],"texture_index":[],"names":[]}
	if _cancelled(token):plan.state="cancelled";return plan
	plan.materials=Cache._materials(scene)
	if use_limit<0 or use_limit>MAX_USES or material_limit<0 or material_limit>MAX_MATERIALS or plan.materials.size()>material_limit:
		# Scene/native owner retain these resources; do not keep an unbounded list.
		plan.materials.clear();plan.state="fallback";return plan
	var seen:Dictionary={}
	for mi:int in plan.materials.size():
		if _cancelled(token):plan.state="cancelled";return plan
		var material:StandardMaterial3D=plan.materials[mi]
		for info:Dictionary in material.get_property_list():
			if not (int(info.usage)&PROPERTY_USAGE_STORAGE):continue
			if int(info.type)!=TYPE_OBJECT and int(info.type)!=TYPE_NIL:continue
			var value:Variant=material.get(info.name)
			if not value is Texture2D:continue
			var id:int=value.get_instance_id()
			if not seen.has(id):
				if not Cache._plain_texture(value):continue
				var key:Variant=value.get_meta(Cache.PIXEL_KEY,"")
				if not Cache._valid_key(key):continue
				if plan.names.size()>=use_limit:
					plan.state="fallback";return plan
				seen[id]=plan.originals.size()
				plan.originals.append(value);plan.keys.append(key)
			elif plan.names.size()>=use_limit:
				plan.state="fallback";return plan
			plan.material_index.append(mi);plan.texture_index.append(seen[id]);plan.names.append(info.name)
	if _cancelled(token):plan.state="cancelled";return plan
	plan.state="ready";return plan

static func apply_prepared(plan:Dictionary)->bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or plan.get("state")!="ready":return false
	if not Cache.enabled:plan.clear();return true
	var replacements:Array[Texture2D]=[];replacements.resize(plan.originals.size())
	var changed:=false
	for i:int in plan.names.size():
		var index:int=plan.texture_index[i]
		var original:Texture2D=plan.originals[index]
		var shared:Texture2D=replacements[index]
		if shared==null:
			shared=Cache._remember(plan.keys[index],original);replacements[index]=shared
		if shared!=original:
			changed=true
			var material:StandardMaterial3D=plan.materials[plan.material_index[i]]
			material.set(plan.names[i],shared)
	if changed:Drainer.synchronize_transfer()
	# A parked ready job must not retain every old texture until publication ends.
	replacements.clear();plan.clear();return true

