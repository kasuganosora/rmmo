extends "res://tools/arrange_town_reference_styles.gd"
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const RoadTools=preload("res://scripts/world_editor/road_tools.gd")
var doc:RefCounted
var additions:Array=[]
var trees:Array=[]
var road_masks:Array=[]
func _initialize()->void:
	OUT="D:/code/rmmo_runtime/review_artifacts/nonperformance_fixes_20261012"
	TARGET="D:/code/rmmo_runtime/cache/world3d/nonperformance_fixes_20261012/map.gltf"
	run.call_deferred()
func reserved(poly:Array)->bool:
	for zone:Dictionary in doc.map_meta.editor_layout.zones:
		if not str(zone.id).begins_with("user_"):continue
		var mask:=PackedVector2Array()
		for p:Array in zone.polygon:mask.append(Vector2(p[0],p[1]))
		if not Geometry2D.intersect_polygons(PackedVector2Array(poly),mask).is_empty():return true
	return false
func move_tree(id:String,candidates:Array)->void:
	var r:Dictionary=doc._find(id);var before:=r.duplicate(true)
	check(not r.is_empty() and not r.get("editor_locked",false) and not r.get("editor_hidden",false),"tree is editable "+id)
	if failures:return
	for at:Array in candidates:
		var y:=ground(doc,Vector3(at[0],0,at[1]))
		if not is_finite(y) or y<-.1:continue
		r.position=[at[0],y-float(r.bounds_position[1])*float(r.size[1]),at[1]]
		var shape:=Foot.record_shape(r)
		var expanded:=Geometry2D.offset_polygon(shape.polygon,.35)
		if expanded.is_empty():continue
		var mask:Array=Array(expanded[0]);var free:=not reserved(mask)
		for obstacle:Dictionary in doc.records:
			if not free:break
			if not obstacle.has("building"):continue
			if shape.bounds.grow(.35).intersects(Geometry.bounds([obstacle])):
				for part:Dictionary in Foot.record_shapes(obstacle):
					if not Geometry2D.intersect_polygons(PackedVector2Array(mask),part.polygon).is_empty():free=false;break
		var trunk:=Poly.rect([at[0]-.7,at[1]-.7,at[0]+.7,at[1]+.7])
		for road:Array in road_masks:
			if not Plan.intersection(trunk,road).is_empty():free=false;break
		if not free:continue
		var delta:=r.duplicate(true);delta.position=before.position
		check(equivalent(delta,before),"tree appearance wind scale and identity preserved "+id)
		trees.append({"uuid":id,"before":before.position,"after":r.position.duplicate()})
		print("TREE_RELOCATED ",JSON.stringify(trees.back()));return
	r.position=before.position;check(false,"no safe tree candidate "+id)
func cut(poly:Array,masks:Array)->Array:
	var parts:Array=[poly]
	for mask:Array in masks:
		var next:Array=[]
		for part:Array in parts:
			if Plan.intersection(part,mask).is_empty():next.append(part)
			else:next.append_array(Poly.subtract(part,mask))
		parts=next
		if parts.is_empty():break
	return parts
func make_paths(paths:Array)->void:
	var merged:Array=[]
	for path:Dictionary in paths:
		var points:Array=[]
		for p:Array in path.points:points.append(Vector2(p[0],p[1]))
		var width:float=path.width*.5;var patches:Array=[]
		for i in points.size()-1:
			var a:Vector2=points[i];var b:Vector2=points[i+1];var tangent:Vector2=(b-a).normalized();var side:=Vector2(-tangent.y,tangent.x)*width
			patches.append([a-side,b-side,b+side,a+side])
		for point:Vector2 in points:
			var polygon:Array=[]
			for i in 12:polygon.append(point+Vector2.from_angle(TAU*i/12.)*width)
			patches.append(polygon)
		for polygon:Array in patches:
			check(not reserved(polygon),"access path outside special-building reservations")
			for piece:Array in cut(polygon,road_masks+merged):merged.append(piece)
	var cells:Dictionary={}
	for polygon:Array in merged:
		var bounds:=Rect2(polygon[0],Vector2.ZERO)
		for point:Vector2 in polygon:bounds=bounds.expand(point)
		for z in range(floori(bounds.position.y/32.),floori(bounds.end.y/32.)+1):
			for x in range(floori(bounds.position.x/32.),floori(bounds.end.x/32.)+1):
				var key:=Vector2i(x,z);var piece:=Plan.intersection(polygon,Poly.rect([x*32.,z*32.,(x+1)*32.,(z+1)*32.]))
				if piece.is_empty() or Poly.area(piece)<.00001:continue
				if not cells.has(key):cells[key]=[]
				cells[key].append(piece)
	var material:Dictionary={}
	for r:Dictionary in doc.records:
		if r.has("road_mesh") and not r.get("surface_paint",[]).is_empty():material=r.surface_paint[0].material;break
	check(not material.is_empty(),"reuse existing town paving material")
	for key:Vector2i in cells:
		var center:=Vector2(key.x*32+16,key.y*32+16);var polygons:Array=[]
		for piece:Array in cells[key]:
			var normalized:Array=[]
			for p:Vector2 in piece:
				var y:=ground(doc,Vector3(p.x,0,p.y));check(is_finite(y) and absf(y)<.03,"path supported by level terrain")
				var q:Vector2=(p-center)/32.;normalized.append([q.x,q.y])
			polygons.append(normalized)
		var r:={"uuid":"residential_access_%d_%d"%[key.x,key.y],"kind":"box","position":[center.x,-.075,center.y],"size":[32.,.2,32.],"rotation":[0.,0.,0.],"color":[.39,.36,.31],"surface_id":"road","road_clearance":3.,"editor_name":"居民入户小路","road_mesh":{"polygons":polygons,"uv_origin":[center.x,0.,center.y]}}
		check(doc._find(r.uuid).is_empty() and Road.valid(r),"valid independent road cell "+r.uuid)
		check(RoadTools.new().paint_default(r,material).ok,"shared editor paving material "+r.uuid)
		additions.append(r.uuid);doc.records.append(r)
func run()->void:
	var recipe:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/access_recipe.json"))
	check(FileAccess.get_sha256(FORMAL)==recipe.formal_sha256,"latest user-saved map matches planned baseline")
	if failures:quit(1);return
	doc=Doc.open_file(FORMAL);check(doc!=null,"open native compact map")
	if failures:quit(1);return
	if "--publish" in OS.get_cmdline_user_args():
		var review:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/access_runtime.json"))
		var result:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/access_result.json"))
		check(review.failures==0 and review.candidate_sha256==FileAccess.get_sha256(TARGET) and result.candidate_sha256==review.candidate_sha256,"candidate passed native runtime review")
		if failures:quit(1);return
		var candidate=Doc.open_file(TARGET);doc.checkpoint_recovery();doc.records=candidate.records;doc.map_meta=candidate.map_meta;doc._next=candidate._next
		check(doc.save(FORMAL)==OK,"native atomic conflict-checked publication")
		var reopened=Doc.open_file(FORMAL);check(reopened!=null and equivalent(doc.records,reopened.records) and equivalent(doc.map_meta,reopened.map_meta),"published map reopens identically")
		write_report("access_published.json",{"failures":failures,"sha256":FileAccess.get_sha256(FORMAL),"candidate_sha256":review.candidate_sha256});quit(failures);return
	var original:Array=doc.records.duplicate(true);var meta:Dictionary=doc.map_meta.duplicate(true)
	for r:Dictionary in original:
		if not r.has("road_mesh"):continue
		for shape:Dictionary in Foot.record_shapes(r):road_masks.append(Array(shape.polygon).slice(0,-1))
	doc.checkpoint_recovery()
	for id:String in recipe.tree_candidates:move_tree(id,recipe.tree_candidates[id])
	make_paths(recipe.paths)
	var preserved:=true
	for r:Dictionary in original:
		if not recipe.tree_candidates.has(r.uuid) and not equivalent(r,doc._find(r.uuid)):preserved=false
	check(preserved and equivalent(meta,doc.map_meta),"all unrelated records and metadata preserved")
	var final:Array=doc.records.duplicate(true)
	check(doc.undo() and equivalent(doc.records,original),"one transaction undo")
	check(doc.redo() and equivalent(doc.records,final),"one transaction redo")
	if failures:quit(1);return
	DirAccess.make_dir_recursive_absolute(TARGET.get_base_dir())
	check(doc.save(TARGET)==OK,"native candidate save")
	var reopened=Doc.open_file(TARGET)
	check(reopened!=null and equivalent(doc.records,reopened.records) and equivalent(meta,reopened.map_meta),"candidate save reopen preserves content")
	write_report("access_result.json",{"failures":failures,"formal_sha256":recipe.formal_sha256,"candidate_sha256":FileAccess.get_sha256(TARGET),"trees":trees,"additions":additions,"paths":recipe.paths})
	print("RESIDENTIAL_ACCESS failures=",failures," additions=",additions.size());quit(failures)
