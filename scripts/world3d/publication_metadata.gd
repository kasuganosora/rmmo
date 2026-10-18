extends RefCounted
## Private unpublished geometry and ownership metadata. The job advances this
## in preparation slices; it grants no navigation, scene or residency authority.
const EMPTY:Dictionary={}
var source:Array=[]
var ids:Dictionary={}
var doors:Array=[]
var geometry_ids:Dictionary={}
var geometry_counts:Dictionary={}
var bounds:Array[AABB]=[]
var namespaces:Dictionary={}
var spec_namespaces:Dictionary={}
var cursor:=0
var error:=""
func begin(values:Array)->void:source=values
func add(value:Dictionary,local_bounds:AABB)->void:
	if not error.is_empty():return
	var pose:Transform3D=value.transform;var extra:Dictionary=value.get("extras",EMPTY)
	var shape:Variant=value.get("shape");var collision:Variant=value.get("collision_mesh")
	if not pose.is_finite() or (shape!=null and not shape is Shape3D) or (collision!=null and not collision is Mesh):error="invalid_spec";return
	var box:AABB=pose*local_bounds
	if not box.position.is_finite() or not box.size.is_finite():error="invalid_spec";return
	var id:String=value.uuid
	if ids.has(id):error="duplicate_uuid";return
	ids[id]=true
	var prefix:=id.get_slice("__",0)
	if not namespaces.has(prefix):namespaces[prefix]={"ids":{},"order":[],"groups":{},"native_owner":false,"ordinary_pin":""}
	var owner:Dictionary=namespaces[prefix]
	owner.ids[id]=true;owner.order.append(id);spec_namespaces[id]=prefix
	owner.native_owner=owner.native_owner or bool(value.get("native_visual",false))
	if owner.ordinary_pin.is_empty():owner.ordinary_pin=preload("res://scripts/world3d/stream_index.gd")._retire_dependency(value,true)
	var geometry:Resource=shape if shape is ConcavePolygonShape3D else value.get("collision_mesh",value.mesh)
	var geometry_id:int=geometry.get_instance_id() if geometry!=null else 0
	geometry_ids[id]=geometry_id;geometry_counts[geometry_id]=int(geometry_counts.get(geometry_id,0))+1
	var door:bool=extra.get("fixture",EMPTY).get("kind")=="door"
	if door and extra.get("rmmo_collision","")!="none":doors.append(value)
	# Keep original merge order, including exact floating-point rounding when
	# the navigation's existing bounds change during other publications.
	if not door and str(extra.get("rmmo_collision",""))!="none" and not bool(extra.get("hostile",false)) and not bool(extra.get("ally",false)):bounds.append(box)
	cursor+=1
func group_member(value:Dictionary,group:String)->void:
	var owner:Dictionary=namespaces[spec_namespaces[value.uuid]]
	if not owner.groups.has(group):owner.groups[group]=value
	owner.ordinary_pin="render_building"
func ready(values:Array)->bool:
	return error.is_empty() and is_same(source,values) and cursor==values.size()
