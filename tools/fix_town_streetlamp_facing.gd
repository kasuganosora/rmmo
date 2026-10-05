extends "res://tools/place_town_streetlamps.gd"
func run()->void:
	if "--publish" in OS.get_cmdline_user_args():
		var night:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/night.json"))
		check(night.failures==0 and night.lamps==23 and night.candidate==FileAccess.get_sha256(TARGET),"real town night and facing acceptance")
		check(night.get("pavement",[]).size()==2,"actual stone pavement illumination acceptance")
		if failures:quit(1);return
		await super.run();return
	var baseline:=FileAccess.get_sha256(FORMAL);var doc=Doc.open_file(FORMAL)
	var previous:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/placement.json"))
	var original:Array=doc.records.duplicate(true);var meta:Dictionary=doc.map_meta.duplicate(true)
	var changed:=0;doc.checkpoint_recovery()
	for lamp:Dictionary in previous.lamps:
		var record:Dictionary=doc._find(lamp.id)
		check(not record.is_empty() and B.vec(record.position).distance_to(B.vec(lamp.position))<.01,"existing authored lamp position")
		var toward_road:Vector3=(B.vec(lamp.road_edge)-B.vec(record.position)).normalized()
		var basis:=Basis.from_euler(B.vec(record.rotation)*PI/180)
		if basis.z.dot(toward_road)<0:record.rotation[1]=fposmod(float(record.rotation[1])+180,360);changed+=1
		lamp.yaw=record.rotation[1]
		check(Basis.from_euler(B.vec(record.rotation)*PI/180).z.dot(toward_road)>.95,"embroidered positive-Z face points at road")
	var after:Array=doc.records.duplicate(true)
	for i in original.size():
		var a:Dictionary=original[i].duplicate(true);var b:Dictionary=after[i].duplicate(true)
		if previous.lamps.any(func(l):return l.id==a.uuid):a.erase("rotation");b.erase("rotation")
		check(equivalent(a,b),"only lamp orientation changed "+str(a.uuid))
	check(equivalent(meta,doc.map_meta),"map metadata unchanged")
	check(doc.undo() and equivalent(doc.records,original),"undo orientation repair")
	check(doc.redo() and equivalent(doc.records,after),"redo orientation repair")
	if failures:quit(1);return
	check(doc.save(TARGET)==OK,"native corrected candidate save")
	check(equivalent(Doc.open_file(TARGET).records,after),"reopen corrected facing")
	previous.baseline=baseline;previous.candidate=FileAccess.get_sha256(TARGET);previous.failures=failures;previous.facing_changed=changed
	report("placement.json",previous)
	print("FACING_FIXED ",changed," failures=",failures);quit(1 if failures else 0)
