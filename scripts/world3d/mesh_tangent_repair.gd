extends RefCounted
## MikkTSpace may emit a zero basis on valid, very thin UV triangles. Repair
## only unusable bases, using double scalar derivatives before normalization.
## Keep every other channel and every already-valid tangent byte unchanged.
static func invalid(t:Vector3,w:float,n:Vector3)->bool:
	return not t.is_finite() or not is_finite(w) or t.length_squared()<.1 or absf(w)<.5 or absf(n.normalized().dot(t.normalized()))>.001

static func perpendicular(v:Array,n:Vector3)->Vector3:
	var dot_:float=v[0]*float(n.x)+v[1]*float(n.y)+v[2]*float(n.z)
	var x:float=v[0]-dot_*float(n.x);var y:float=v[1]-dot_*float(n.y);var z:float=v[2]-dot_*float(n.z)
	var length_:float=sqrt(x*x+y*y+z*z)
	if not is_finite(length_) or length_<=0.:return Vector3.ZERO
	return Vector3(x/length_,y/length_,z/length_)

static func repair(arrays:Array)->Array:
	if arrays[Mesh.ARRAY_TANGENT]==null or arrays[Mesh.ARRAY_NORMAL]==null or arrays[Mesh.ARRAY_TEX_UV]==null:return arrays
	var p:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL];var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var original:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
	if original.size()!=p.size()*4 or normals.size()!=p.size() or uv.size()!=p.size():return arrays
	var bad:Dictionary={}
	for i in p.size():
		if invalid(Vector3(original[i*4],original[i*4+1],original[i*4+2]),original[i*4+3],normals[i]):bad[i]={"quality":-1.,"tangent":Vector3.ZERO,"sign":1.}
	if bad.is_empty():return arrays
	var ids:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	if ids.is_empty():ids=PackedInt32Array(range(p.size()))
	for k in range(0,ids.size()-2,3):
		var abc:=[ids[k],ids[k+1],ids[k+2]]
		if not abc.any(func(i):return bad.has(i)):continue
		# Subtraction and determinants stay double, avoiding Vector3 float32
		# cancellation on the thin bevels of the authored stone modules.
		var e:Array=[];var f:Array=[]
		for axis in 3:e.append(float(p[abc[1]][axis])-float(p[abc[0]][axis]));f.append(float(p[abc[2]][axis])-float(p[abc[0]][axis]))
		var du:float=float(uv[abc[1]].x)-float(uv[abc[0]].x);var dv:float=float(uv[abc[1]].y)-float(uv[abc[0]].y)
		var su:float=float(uv[abc[2]].x)-float(uv[abc[0]].x);var sv:float=float(uv[abc[2]].y)-float(uv[abc[0]].y)
		var det:float=du*sv-dv*su;var cross_:Array=[e[1]*f[2]-e[2]*f[1],e[2]*f[0]-e[0]*f[2],e[0]*f[1]-e[1]*f[0]]
		var area2:float=cross_[0]*cross_[0]+cross_[1]*cross_[1]+cross_[2]*cross_[2]
		if not is_finite(det) or det==0. or not is_finite(area2) or area2<=0.:continue
		var t:Array=[];var b:Array=[];var orientation:float=1. if det>0. else -1.
		for axis in 3:t.append((e[axis]*sv-f[axis]*dv)*orientation);b.append((f[axis]*du-e[axis]*su)*orientation)
		for i:int in abc:
			if not bad.has(i) or area2<=bad[i].quality:continue
			var n:=normals[i].normalized();var tangent:=perpendicular(t,n)
			if tangent.is_zero_approx():continue
			var bitangent:=n.cross(tangent);var handed:float=float(bitangent.x)*b[0]+float(bitangent.y)*b[1]+float(bitangent.z)*b[2]
			if not is_finite(handed) or handed==0.:continue
			# Godot stores the binormal as tangent.cross(normal) * w, which is
			# the opposite sign to the common normal.cross(tangent) convention.
			bad[i]={"quality":area2,"tangent":tangent,"sign":-1. if handed>0. else 1.}
	var tangents:=original.duplicate()
	for i:int in bad:
		var t:Vector3=bad[i].tangent;var w:float=bad[i].sign
		if t.is_zero_approx():
			# A collapsed UV island has no derivative. Use a deterministic normal-
			# orthogonal basis; retain a finite source handedness when available.
			var n:=normals[i].normalized()
			if not n.is_finite() or n.length_squared()<.5:continue
			var axis:=Vector3.RIGHT if absf(n.x)<=minf(absf(n.y),absf(n.z)) else (Vector3.UP if absf(n.y)<=absf(n.z) else Vector3.BACK)
			t=(axis-n*n.dot(axis)).normalized();w=-1. if is_finite(original[i*4+3]) and original[i*4+3]<0. else 1.
		tangents[i*4]=t.x;tangents[i*4+1]=t.y;tangents[i*4+2]=t.z;tangents[i*4+3]=w
	var result:=arrays.duplicate();result[Mesh.ARRAY_TANGENT]=tangents;return result
