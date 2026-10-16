extends "res://review_artifacts/road_paint_20261017/road_tools_ref.gd"
## Diagnostic-only copy of paint_default. All markers excluded from OFF runs.
var paint_samples:Array=[]

func paint_default(record:Dictionary,material:Dictionary)->Dictionary:
	var times:Dictionary={};var start:=Time.get_ticks_usec()
	var node:=MeshInstance3D.new();node.mesh=Surface.mesh(record,null)
	times.mesh_ms=(Time.get_ticks_usec()-start)/1000.;start=Time.get_ticks_usec()
	var geometry:=Paint.geometry(node);node.free()
	times.geometry_ms=(Time.get_ticks_usec()-start)/1000.;start=Time.get_ticks_usec()
	if not geometry.ok:return geometry
	var surface:Dictionary=geometry.surfaces[0];var entries:Array=[];var tile:Array=material.get("tile_size",[1,1])
	if surface.faces.size()>Paint.MAX_OVERRIDES:return {"ok":false,"code":"road_paint_face_limit","error":"单块路面需要 %d 个刷面，超过 %d 个预算"%[surface.faces.size(),Paint.MAX_OVERRIDES]}
	for face in surface.faces:
		entries.append({"mesh":".","surface":0,"face":face,"geometry":surface.signature,"material":material.duplicate(true),"mapping":"uv","scale":[1.0/tile[0],1.0/tile[1]],"offset":[0,0],"rotation":0.0})
	record.surface_paint=entries
	times.entries_ms=(Time.get_ticks_usec()-start)/1000.;start=Time.get_ticks_usec()
	var valid:=Paint.valid(record)
	times.valid_ms=(Time.get_ticks_usec()-start)/1000.;start=Time.get_ticks_usec()
	var missing:bool=Paint.missing([record]).is_empty() if valid else false
	times.missing_ms=(Time.get_ticks_usec()-start)/1000.
	times.polygons=record.road_mesh.polygons.size();times.faces=surface.faces.size()
	times.surfaces=geometry.surfaces.size();times.surface_triangles=geometry.surfaces.map(func(s):return s.indices.size()/3)
	paint_samples.append(times)
	return {"ok":true} if valid and missing else Data.fail("路面材质无效或贴图依赖缺失")
