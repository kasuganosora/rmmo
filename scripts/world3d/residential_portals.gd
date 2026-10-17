extends RefCounted
## Optional frozen opening hints, relative to the owning record's closed pose.
## They select a location; actual floor/collision checks remain authoritative.
const S=preload("res://scripts/world3d/document_schema.gd")

static func valid(record:Dictionary)->bool:
	if not record.has("residential_portals"):return true
	var rows:Variant=record.residential_portals
	if not rows is Array or rows.size()>16:return false
	var ids:Dictionary={}
	for row in rows:
		if not row is Dictionary or row.size()!=4:return false
		if not row.get("id") is String or row.id.is_empty() or row.id.length()>180 or ids.has(row.id):return false
		if not S.validate(row.get("position"),S.vector(-1000,1000)).is_empty() or not S.validate(row.get("outward"),S.vector(-1,1)).is_empty():return false
		var n:Vector3=Vector3(row.outward[0],row.outward[1],row.outward[2])
		if absf(n.y)>.00001 or absf(n.length()-1.)>.00001 or not S.validate(row.get("width"),S.number(.9,20)).is_empty():return false
		ids[row.id]=true
	return record.get("building",{}).get("floor",-1)==0 and not record.has("fixture")
