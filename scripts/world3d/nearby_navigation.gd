extends RefCounted
## An independent foreground bake; it never resets the full-map tile queue.
var clip:AABB
var mesh:NavigationMesh
var source:=NavigationMeshSourceGeometryData3D.new()
var cursor:=0
var baking:=false
var complete:=false
var started_ms:=Time.get_ticks_msec()

func _init(template:NavigationMesh,area:AABB)->void:
	clip=area
	mesh=template.duplicate();mesh.clear()
	mesh.filter_baking_aabb=clip;mesh.border_size=0

func step(owner:Node,budget_usec:int=2000)->void:
	if complete:return
	if baking:
		complete=not NavigationServer3D.is_baking_navigation_mesh(mesh)
		return
	if budget_usec<=0:return
	var started:=Time.get_ticks_usec()
	var initial_cursor:=cursor
	while cursor<owner._specs.size() and (cursor==initial_cursor or Time.get_ticks_usec()-started<budget_usec):
		var spec:Dictionary=owner._specs[cursor];cursor+=1
		if not owner._collides(spec):continue
		var box:AABB=spec.transform*spec.mesh.get_aabb()
		if clip.intersects(box) and not owner._add_source(source,spec):cursor-=1;return
	if cursor<owner._specs.size():return
	var prepared:NavigationMeshSourceGeometryData3D=owner._prepare_source(source)
	if prepared==null:return
	source=prepared
	baking=true
	NavigationServer3D.bake_from_source_geometry_data_async(mesh,source)
