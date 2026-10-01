extends RefCounted
## Morton ordering affects search only. Original IDs resolve exact contact ties.
static func spread(value:int)->int:
	value=(value | (value<<16)) & 0x030000ff
	value=(value | (value<<8)) & 0x0300f00f
	value=(value | (value<<4)) & 0x030c30c3
	value=(value | (value<<2)) & 0x09249249
	return value
static func order(points:PackedVector3Array)->PackedInt32Array:
	var low:=Vector3(INF,INF,INF);var high:=-low
	for p in points:low=low.min(p);high=high.max(p)
	var size:=(high-low).max(Vector3(.000001,.000001,.000001))
	var keys:=PackedInt64Array();keys.resize(points.size())
	for i in points.size():
		var p:=(points[i]-low)/size*1023
		var morton:=spread(clampi(int(p.x),0,1023)) | (spread(clampi(int(p.y),0,1023))<<1) | (spread(clampi(int(p.z),0,1023))<<2)
		keys[i]=(morton<<32)|i
	keys.sort()
	var result:=PackedInt32Array();result.resize(points.size())
	for i in keys.size():result[i]=keys[i]&0xffffffff
	return result
