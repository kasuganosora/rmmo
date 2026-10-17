extends Node
## Read-only explanations of existing checks. Never turns an error into success.
const City=preload("res://scripts/world3d/city_layout.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const NESTED=["last_failure","terrain_contact","lower_witness","upper_witness","grade_witness","seam_witness","witness","hole_witness"]
const VALUES=["measured_step","limit","grade","max_grade","max_seam_step","max_height_error","minimum_length","terrain_height","floor_bottom","foundation_bottom","interval","requested","limits"]
var editor:Node3D
var entries:Dictionary={}
var overlay:MeshInstance3D
var displayed_version:=""

static func category(result:Dictionary)->String:
	var code:String=str(result.get("code",""))
	if code.contains("unsupported"):return "unsupported"
	if code=="search_exhausted":return "search_exhausted"
	if code.contains("stale") or code in ["base_changed","source_changed","candidate_missing"]:return "stale"
	if code.contains("invalid"):return "invalid_request"
	if code.contains("conflict") or not result.get("conflicts",[]).is_empty() or code in ["entrance_step","entrance_clearance","entrance_obstructed","kerb_conflict","reserved_zone","road_house_clearance"]:return "conflict"
	return "constraint"

static func collect(value:Dictionary,items:Array,path:String="",depth:int=0)->void:
	if depth>8 or items.size()>=32:return
	var item:Dictionary={"source":path,"code":str(value.get("code","")),"message":str(value.get("error","")),"category":category(value),"object_ids":[],"values":{}}
	for key:String in ["conflicts","terrain_ids"]:
		for id:Variant in value.get(key,[]):
			if id is String and id not in item.object_ids:item.object_ids.append(id)
	for key:String in ["terrain_id","record_id","foundation_id"]:
		if value.get(key) is String and not value[key].is_empty() and value[key] not in item.object_ids:item.object_ids.append(value[key])
	var position:Variant=value.get("position")
	if position is Array and position.size()==3 and position.all(func(v):return (v is int or v is float) and is_finite(v)):item.position=position.duplicate()
	for key:String in VALUES:
		if value.has(key):item.values[key]=value[key]
	if not item.object_ids.is_empty() or item.has("position") or not item.values.is_empty() or not item.message.is_empty():items.append(item)
	for key:String in NESTED:
		if value.get(key) is Dictionary:collect(value[key],items,path+"/"+key,depth+1)

static func normalize(result:Dictionary,operation:String)->Dictionary:
	var items:Array=[];collect(result,items)
	return {"version":1,"operation":operation,"category":category(result),"code":str(result.get("code","constraint")),"message":str(result.get("error","操作未通过")),"stage":str(result.get("stage","")),"items":items,"truncated":items.size()>=32}

func version()->String:
	return City.token([editor._doc.get_instance_id(),editor._doc.authoring_revision,editor._authoring.settings])

func explain(result:Dictionary,operation:String)->Dictionary:
	if result.get("ok",false):return result
	var info:=normalize(result,operation)
	var base:=version();var token:=City.token([base,info])
	for item:Dictionary in info.items:
		var records:Array=editor._doc.records.filter(func(r):return r.uuid in item.object_ids)
		item.objects=records.map(func(r):return {"id":r.uuid,"name":r.get("editor_name",r.uuid)})
		item.locatable=item.has("position") or not records.is_empty()
	if not entries.has(token) and entries.size()>=8:entries.erase(entries.keys()[0])
	entries[token]={"base_version":base,"diagnostic":info}
	return result.merged({"diagnostic":info,"diagnostic_token":token},true)

func focus(args:Dictionary)->Dictionary:
	var token:String=args.get("diagnostic_token","");var index:int=args.get("index",0)
	if not entries.has(token):return {"ok":false,"code":"diagnostic_missing","error":"诊断已释放，请重新执行检查"}
	var entry:Dictionary=entries[token]
	if entry.base_version!=version():return {"ok":false,"code":"diagnostic_stale","error":"地图或查看范围已变化，请重新检查"}
	if index<0 or index>=entry.diagnostic.items.size():return {"ok":false,"code":"invalid_arguments","error":"诊断条目不存在"}
	var ready:Dictionary=editor._city.guard()
	if not ready.ok:return ready
	var item:Dictionary=entry.diagnostic.items[index];var box:AABB
	if item.has("position"):box=AABB(City.vec(item.position)-Vector3.ONE,Vector3.ONE*2.)
	else:
		var records:Array=editor._doc.records.filter(func(r):return r.uuid in item.object_ids)
		if records.is_empty():return {"ok":false,"code":"diagnostic_unlocated","error":"此检查没有提供可定位对象或几何见证"}
		box=Geometry.bounds(records).grow(.05)
	var camera:Dictionary=editor._city.set_camera({"center":City.xyz(box.get_center()),"distance":clampf(box.size.length()*1.4,4.,10000.),"span":clampf(box.size.length()*1.4,4.,10000.)})
	if not camera.ok:return camera
	clear();var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for axis in 3:
		for a in 2:
			for b in 2:
				var p:=box.position;p[(axis+1)%3]+=box.size[(axis+1)%3]*a;p[(axis+2)%3]+=box.size[(axis+2)%3]*b
				mesh.surface_add_vertex(p);p[axis]+=box.size[axis];mesh.surface_add_vertex(p)
	mesh.surface_end();overlay=MeshInstance3D.new();overlay.mesh=mesh
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(1.,.4,.08);material.no_depth_test=true
	overlay.material_override=material;overlay.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;editor.add_child(overlay);displayed_version=entry.base_version
	return {"ok":true,"diagnostic_token":token,"index":index,"bounds":{"position":City.xyz(box.position),"size":City.xyz(box.size)},"camera":camera.camera}

func clear()->Dictionary:
	if is_instance_valid(overlay):overlay.free()
	overlay=null;displayed_version=""
	return {"ok":true}

func _process(_delta:float)->void:
	if not displayed_version.is_empty() and displayed_version!=version():clear()

func _exit_tree()->void:clear()
