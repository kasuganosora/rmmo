extends "res://tools/apply_axel_reference_layout.gd"
## S1 landscape scene authoring; all changes use current editor operations.
var entry_snapshot:Dictionary={}
var permitted:Dictionary={}
func bank_ground(point:Vector3,id:String)->float:
	var record:Dictionary=editor._doc._find(id)
	var rows:Array=preload("res://scripts/world3d/rock_bank_mesh.gd").sections(record)
	var origin:=City.vec(record.position);var highest:float=-INF
	for i in rows.size()-1:
		var a:Vector3=rows[i].outer+origin;var b:Vector3=rows[i].inner+origin
		var c:Vector3=rows[i+1].inner+origin;var d:Vector3=rows[i+1].outer+origin
		for tri:Array in [[a,b,c],[a,c,d]]:
			var hit:Variant=Geometry3D.ray_intersects_triangle(Vector3(point.x,1000,point.z),Vector3.DOWN,tri[0],tri[1],tri[2])
			if hit!=null:highest=maxf(highest,hit.y)
	return highest
func before_placements(recipe:Dictionary)->void:
	entry_snapshot=editor._doc.recovery_snapshot()
	report.scope="S1 classic bridge banks, vegetation, laundry and distant spire; existing house and bridge geometry unchanged"
	for row:Dictionary in recipe.get("pre_moves",[]):
		var r:Dictionary=editor._doc._find(row.id);var box:AABB=Foot.record_shape(r).bounds
		var point:=City.vec(row.point);point.y=Props.ground(editor._doc,point)-.02
		var at:=City.vec(r.position)+point-Vector3(box.get_center().x,box.position.y,box.get_center().z)
		await operation("set_object_transform",{"id":row.id,"position":City.xyz(at)})
		permitted[row.id]=true;report.placements.append({"id":row.id,"key":row.key,"position":City.xyz(at),"scale":r.size})
	for bank:Dictionary in recipe.get("banks",[]):
		if recipe.get("fit_bank_inner_ground",false):
			check(bank.get("direction_mode","")=="fixed","explicit bank grounding direction")
			bank.inner_heights=[]
			var angle:float=deg_to_rad(bank.cap_angle)
			for i in bank.points.size():
				var inner:=City.vec(bank.points[i])+Vector3(cos(angle),0,sin(angle))*float(bank.inner_widths[i])
				bank.inner_heights.append(Props.ground(editor._doc,inner)-.015)
		var preview:=await operation("preview_rock_bank",bank)
		check(preview.get("ok",false),"native S1 bank preview "+str(bank.id))
		if failed:return
		var result:=await operation("set_rock_bank",bank)
		check(result.get("ok",false),"native S1 bank creation "+str(bank.id))
		if failed:return
		permitted[bank.id]=true
		if not report.has("banks"):report.banks=[]
		report.banks.append({"id":bank.id,"preview":preview,"created":result})
	for row:Dictionary in recipe.placements:
		if not row.has("support_bank"):continue
		var height:=bank_ground(City.vec(row.point),row.support_bank)
		check(is_finite(height),"grass roots supported by actual native bank cap "+str(row.key))
		if failed:return
		row.point[1]=height-.035;row.grounded=false
func after_placements(recipe:Dictionary)->void:
	for row:Dictionary in report.placements:permitted[row.id]=true
	await super.after_placements(recipe)
	if failed:return
	var doc=editor._doc
	report.changed_records=[];report.deleted_records=[];report.new_records=[]
	var old_ids:Dictionary={}
	for old:Dictionary in entry_snapshot.records:
		old_ids[old.uuid]=true;var now:Dictionary=doc._find(old.uuid)
		if City.token(old)==City.token(now):continue
		check(permitted.has(old.uuid),"change limited to explicitly authored S1 instances "+str(old.uuid))
		if now.is_empty():report.deleted_records.append(old.uuid)
		else:report.changed_records.append(old.uuid)
	for row:Dictionary in doc.records:
		if old_ids.has(row.uuid):continue
		check(permitted.has(row.uuid),"new record belongs to scoped S1 operation "+str(row.uuid));report.new_records.append(row.uuid)
	check(City.token(entry_snapshot.map_meta)==City.token(doc.map_meta),"houses, roads, hydrology, birth and all metadata unchanged")
