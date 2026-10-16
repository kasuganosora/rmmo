extends SceneTree
## Fast read-only geometric preflight; final authoring still uses real HTTP.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Batch=preload("res://scripts/world3d/terrain_stroke_batch.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Fit=preload("res://scripts/world3d/fortification_terrain.gd")
const Plan=preload("res://scripts/world3d/fortification_plan.gd")
const F=preload("res://scripts/world3d/fortification_data.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Layer=preload("res://scripts/world3d/terrain_river_layer.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
func _init()->void:call_deferred("run")
func run()->void:
	var recipe:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/fortification_content_recipe.json"))
	if recipe.source_sha256!=FileAccess.get_sha256("D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"):emit({"ok":false,"error":"Source changed"});return
	var doc=Doc.new();doc.records=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/source_records.json"));doc.map_meta=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/source_metadata.json"))
	var original:Array=doc.records.duplicate(true);var touched:Dictionary={};var result:Dictionary={}
	for batch:Dictionary in recipe.terrain_batches:
		for stroke:Dictionary in batch.strokes:
			var applied:=Batch.prepare(doc.records,doc._find(stroke.id),stroke)
			if not applied.ok:emit(applied);return
			for e:Dictionary in applied.entries:
				for i in doc.records.size():
					if doc.records[i].uuid==e.record.uuid:doc.records[i]=e.record;break
				touched[e.record.uuid]=true
	var owned_changes:Array=[]
	var previous:Dictionary={};for r:Dictionary in original:previous[r.uuid]=r
	for river:Dictionary in doc.map_meta.terrain_rivers:
		for tile:Dictionary in river.terrains:
			var next:Dictionary=doc._find(tile.after.uuid)
			for i in tile.after.terrain_mesh.heights.size():
				if not Layer.same(tile.before.terrain_mesh.heights[i],tile.after.terrain_mesh.heights[i]) and not Layer.same(next.terrain_mesh.heights[i],previous[tile.after.uuid].terrain_mesh.heights[i]):owned_changes.append({"river":river.id,"tile":tile.after.uuid,"vertex":i})
	var settings:=F.defaults().merged(recipe.fortification_request,true);settings.layout_version=1
	result=Plan.new().build(settings)
	if not result.ok:emit(result);return
	var reserve_conflicts:Array=[]
	for zone:Dictionary in City.resolve(doc.map_meta).get("zones",[]):
		if zone.get("purpose","")!="no_build":continue
		var polygon:=PackedVector2Array();for p:Array in zone.polygon:polygon.append(Vector2(p[0],p[1]))
		var box:=Rect2(polygon[0],Vector2.ZERO);for p:Vector2 in polygon:box=box.expand(p)
		for r:Dictionary in result.records:
			for shape:Dictionary in preload("res://scripts/world_editor/building_footprint.gd").record_shapes(r):
				var bounds:AABB=shape.bounds
				if not box.intersects(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)),true):continue
				if not Geometry2D.intersect_polygons(polygon,shape.polygon).is_empty():reserve_conflicts.append({"zone":zone.id,"part":r.fortification.part});break
	var fitted:=Fit.fit(result.records,doc.records.filter(func(r):return r.has("terrain_mesh")),settings.base_height,settings.foundation,settings)
	var terrain:Array=doc.records.filter(func(r):return r.has("terrain_mesh"));var extremes:Array=[]
	for r:Dictionary in result.records:
		if str(r.fortification.part).begins_with("water_"):continue
		var c:=City.vec(r.position);var basis:=Basis.from_euler(City.vec(r.rotation)*PI/180);var dx:=maxf(.1,r.size[0]/2);var dz:=maxf(.1,r.size[2]/2)
		var h:=Fit.height(terrain,c);var a:=Fit.height(terrain,c+basis.x*dx);var b:=Fit.height(terrain,c-basis.x*dx);var e:=Fit.height(terrain,c+basis.z*dz);var d:=Fit.height(terrain,c-basis.z*dz)
		var grade:=Vector2((a-b)/(2*dx),(e-d)/(2*dz)).length();var nonlinear:=maxf(absf((a+b)/2-h),absf((e+d)/2-h))
		if grade>.15 or nonlinear>.15:extremes.append({"part":r.fortification.part,"position":r.position,"size":r.size,"grade":grade,"nonlinear":nonlinear})
	var actual_failures:Array=[]
	var water_support:Array=result.records.filter(func(r):return r.has("water_gate") or str(r.fortification.part).begins_with("water_pier_") or str(r.fortification.part).begins_with("water_crown_"))
	for item:Dictionary in extremes:
		var matching:Array=result.records.filter(func(r):return r.fortification.part==item.part)
		if matching.is_empty():continue
		var record:Dictionary=matching[0]
		# Include actual water structural supports so crown-top battlements retain
		# the same exemption as the full native fitter, never an AABB-only guess.
		var isolated:Array=water_support.duplicate();isolated.append(record)
		var checked:=Fit.fit(isolated,terrain,settings.base_height,settings.foundation,settings)
		if not checked.ok:actual_failures.append(item.merged({"error":checked.error}))
	var banks:=Fit.water_jambs(settings);var bank_samples:Array=[]
	for j:Dictionary in banks.jambs:
		var samples:Array=[]
		for offset:float in [-j.half,0.,j.half]:
			var p:Vector2=j.point+j.normal*offset;samples.append(Fit.height(terrain,Vector3(p.x,0,p.y)))
		bank_samples.append({"id":j.id,"point":[j.point.x,j.point.y],"target":j.base,"samples":samples})
	emit({"ok":fitted.ok and reserve_conflicts.is_empty() and owned_changes.is_empty(),"fit_ok":fitted.ok,"fit_error":fitted.get("error",""),"recipe_sha256":FileAccess.get_sha256(OUT+"/fortification_content_recipe.json"),"reserve_conflicts":reserve_conflicts,"river_owned_changes":owned_changes,"banks":bank_samples,"extremes":extremes,"actual_fit_failures":actual_failures,"first_native_failure":diagnose_fit(result.records,terrain,settings.base_height,settings.foundation,settings) if not fitted.ok else {},"terrain_changed":touched.keys(),"source_parts":result.records.size()})
func emit(result:Dictionary)->void:
	var f:=FileAccess.open(OUT+"/fortification_geometric_preflight.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close()
	print(JSON.stringify({"ok":result.get("ok",false),"fit_error":result.get("fit_error",result.get("error","")),"owned_changes":result.get("river_owned_changes",[]).size(),"extremes":result.get("extremes",[]).size()}));quit(0 if result.get("ok",false) else 1)

# Read-only diagnostic mirror of native Fit.fit; no altered acceptance rule.
func diagnose_fit(records:Array,terrains:Array,base:float,foundation:float,settings:Dictionary={})->Dictionary:
	var banks:=Fit.water_jambs(settings)
	if not banks.ok:return banks
	# An elevated arch is not a license to suspend its dry-bank jambs.
	# Match both banks before fitting adjacent walls to the exact deck datum.
	for jamb:Dictionary in banks.jambs:
		for offset:float in [-jamb.half,0.,jamb.half]:
			var at:Vector2=jamb.point+jamb.normal*offset;var h:=Fit.height(terrains,Vector3(at.x,0,at.y))
			if not is_finite(h) or absf(h-jamb.base)>.12:return City.fail("水关 %s 的两岸墙脚须有与局部岸基准一致的承托台地（高差 ≤ 0.12 米），请先整坡"%jamb.id)
	var next:Array=records.duplicate(true);var rigid:Dictionary={};var regex:=RegEx.new();regex.compile("^(access_tower_[0-9]+|tower_(?:parapet_|merlon_)?[0-9]+|(?:door|lintel)_[a-zA-Z0-9]+)")
	for r:Dictionary in next:
		var match_:RegExMatch=regex.search(r.fortification.part)
		if match_==null:continue
		var key:=match_.get_string(1)
		key=key.replace("tower_parapet_","tower_").replace("tower_merlon_","tower_").replace("door_","gate_").replace("lintel_","gate_")
		if not rigid.has(key):rigid[key]={"records":[],"height":-INF,"low":INF}
		rigid[key].records.append(r)
		for p:Vector3 in preload("res://scripts/world_editor/selection_geometry.gd").corners(r):
			var h:=Fit.height(terrains,p)
			if not is_finite(h):return City.fail("城楼或城门缺少完整地形承托")
			rigid[key].height=maxf(rigid[key].height,h)
			rigid[key].low=minf(rigid[key].low,h)
	var moved:Dictionary={}
	for group:Dictionary in rigid.values():
		if group.height-group.low>.12:return City.fail("城门和城楼需局部平整的承托台地（高差 ≤ 0.12 米），请先整平；墙段可随坡地延伸")
		for r:Dictionary in group.records:r.position[1]+=group.height-base;moved[r.uuid]=true
	var water_parts:Array=next.filter(func(r):return r.has("water_gate") or str(r.fortification.part).begins_with("water_pier_") or str(r.fortification.part).begins_with("water_crown_"))
	var water_support:Array=[]
	for part:Dictionary in water_parts:
		var polygons:Array=[]
		if part.has("channel_mesh"):
			for shape:Dictionary in preload("res://scripts/world_editor/building_footprint.gd").record_shapes(part):polygons.append(shape.polygon)
		water_support.append({"inverse":Terrain.transform(part).affine_inverse(),"half":City.vec(part.size)*.5,"polygons":polygons})
	for r:Dictionary in next:
		if moved.has(r.uuid) or str(r.fortification.part).begins_with("water_"):continue
		var over_water:=false
		for support:Dictionary in water_support:
			var relative:Vector3=support.inverse*City.vec(r.position)
			if absf(relative.x)>=support.half.x+.01 or absf(relative.z)>=support.half.z+.05:continue
			# Curved crowns fill the crescent outside the water arch's straight
			# chord. Battlements resting there share the fixed arch elevation;
			# lowering the bed must not lower them through their stone crown.
			var p:=Vector2(r.position[0],r.position[2])
			if support.polygons.is_empty() or support.polygons.any(func(poly):return Geometry2D.is_point_in_polygon(p,poly)):over_water=true;break
		if over_water:continue
		var center:=City.vec(r.position);var basis:=Basis.from_euler(City.vec(r.rotation)*PI/180);var h:=Fit.height(terrains,center)
		var dx:=maxf(.1,r.size[0]*.5);var dz:=maxf(.1,r.size[2]*.5)
		var a:=Fit.height(terrains,center+basis.x*dx);var b:=Fit.height(terrains,center-basis.x*dx);var c:=Fit.height(terrains,center+basis.z*dz);var d:=Fit.height(terrains,center-basis.z*dz)
		if not [h,a,b,c,d].all(func(v):return is_finite(v)):return City.fail("城墙路径缺少完整地形承托")
		var anchor_a:=Fit.jamb_height(banks.jambs,center+basis.x*dx);var anchor_b:=Fit.jamb_height(banks.jambs,center-basis.x*dx)
		var anchored:=is_finite(anchor_a) or is_finite(anchor_b)
		if anchored:
			if is_finite(anchor_a):a=anchor_a
			if is_finite(anchor_b):b=anchor_b
			# The bank-side strip ends exactly at the crown rather than leaving
			# the old center-sampled plane's small step at the structural joint.
			h=(a+b)*.5
		var grade:=Vector2((a-b)/(dx*2),(c-d)/(dz*2))
		if anchored:grade.y=0.
		if grade.length()>.15:return {"ok":false,"part":r.fortification.part,"record":r,"grade":[grade.x,grade.y],"samples":[h,a,b,c,d],"anchored":anchored}
		if maxf(absf((a+b)*.5-h),absf((c+d)*.5-h))>minf(foundation*.5,.15):return {"ok":false,"part":r.fortification.part,"record":r,"grade":[grade.x,grade.y],"samples":[h,a,b,c,d],"anchored":anchored}
		r.position[1]+=h-base;r.terrain_grade=[grade.x,grade.y]
	var offsets:Dictionary={}
	for i in records.size():offsets[records[i].uuid]=float(next[i].position[1])-float(records[i].position[1])
	return {"ok":true,"records":next,"height_offsets":offsets}
