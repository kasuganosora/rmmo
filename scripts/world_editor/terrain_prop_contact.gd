extends RefCounted
## Refine the terrain guard's deliberately inflated swept-cell broad phase for
## ordinary props only. The lower faces of the authored oriented bounds are
## conservative contact surfaces; generated structures keep their own guards.
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const Clip=preload("res://scripts/world3d/road_plan.gd")
const Furrows=preload("res://scripts/world3d/terrain_furrows.gd")
const CONTACT=.005
const ROUNDING=.00001
const COMPLEX=["building","building_shape","house_prefab","fixture","fortification","terrain_mesh","terrain_grade","road_mesh","road_source","channel_mesh","rock_bank","tile3d"]

static func lower_faces(record:Dictionary)->Array:
	if record.get("kind") not in ["box","asset"] or COMPLEX.any(func(key):return record.has(key)):return []
	var size:=Geometry.vector(record,"size")
	if size.x<=0 or size.y<=0 or size.z<=0:return []
	var bounds:=AABB(-size*.5,size)
	if record.kind=="asset":
		if not record.has("bounds_position") or not record.has("bounds_size"):return []
		bounds=AABB(Geometry.vector(record,"bounds_position")*size,Geometry.vector(record,"bounds_size")*size)
	if bounds.size.x<=0 or bounds.size.y<=0 or bounds.size.z<=0:return []
	var pose:=Transform3D(Basis.from_euler(Geometry.vector(record,"rotation")*PI/180),Geometry.vector(record,"position"))
	var center:=pose*bounds.get_center();var faces:Array=[]
	# Endpoint bit ordering is deliberately not assumed. Each axis defines two
	# complete faces; tilted props can have several faces in their lower envelope.
	for axis in 3:
		var a:=(axis+1)%3;var b:=(axis+2)%3
		for end in 2:
			var corners:Array[Vector3]=[]
			for uv in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
				var p:=bounds.position;p[axis]+=bounds.size[axis]*end;p[a]+=bounds.size[a]*uv.x;p[b]+=bounds.size[b]*uv.y;corners.append(pose*p)
			var normal:=(corners[1]-corners[0]).cross(corners[2]-corners[0])
			if normal.dot(corners[0]-center)<0:normal=-normal
			if normal.y>=-1e-8:continue
			var polygon:Array=corners.map(func(p):return Vector2(p.x,p.z))
			if Geometry2D.is_polygon_clockwise(PackedVector2Array(polygon)):polygon.reverse()
			faces.append({"polygon":polygon,"point":corners[0],"normal":normal,"base":axis==1 and end==0})
	# Side-lying/inverted assets have no authored downward base we can prove.
	return faces if faces.any(func(face):return face.base and -face.normal.y/face.normal.length()>.0001) else []

static func height(point:Vector3,normal:Vector3,at:Vector2)->float:
	# Relative coordinates avoid cancellation at translated map coordinates.
	return float(point.y)-(float(normal.x)*(float(at.x)-point.x)+float(normal.z)*(float(at.y)-point.z))/normal.y

static func preserves(record:Dictionary,result:Dictionary,prop:Dictionary)->bool:
	var faces:=lower_faces(prop)
	if faces.is_empty() or Furrows.maximum_height(record)>0 or Furrows.maximum_height(result.record)>0:return false
	var world:=Terrain.transform(record);var t:Dictionary=record.terrain_mesh
	for at in result.cells:
		var x:=int(at)%int(t.columns);var z:=int(at)/int(t.columns)
		if t.holes[at] and result.record.terrain_mesh.holes[at]:continue
		var before:Array=Terrain.cell(record,x,z).map(func(p):return world*p)
		var after:Array=Terrain.cell(result.record,x,z).map(func(p):return world*p)
		for indices in [[0,1,2],[0,2,3]]:
			var p:Vector3=before[indices[0]];var q:Vector3=after[indices[0]]
			var n:Vector3=(before[indices[1]]-p).cross(before[indices[2]]-p)
			var m:Vector3=(after[indices[1]]-q).cross(after[indices[2]]-q)
			if absf(n.y)<1e-8 or absf(m.y)<1e-8:return false
			var triangle:Array=indices.map(func(i):return Vector2(before[i].x,before[i].z))
			for face:Dictionary in faces:
				var overlap:=Clip.intersection(face.polygon,triangle)
				if overlap.size()<3 or Poly.area(overlap)<1e-10:continue
				if t.holes[at]!=result.record.terrain_mesh.holes[at]:return false
				# Contact-vs-existing-penetration is piecewise affine. Include
				# crossings of both old-contact thresholds, not just polygon corners.
				var samples:Array=overlap.duplicate()
				for i in overlap.size():
					var a:Vector2=overlap[i];var b:Vector2=overlap[(i+1)%overlap.size()]
					var ga:=height(p,n,a)-height(face.point,face.normal,a)
					var gb:=height(p,n,b)-height(face.point,face.normal,b)
					for threshold in [-CONTACT,CONTACT]:
						if (ga-threshold)*(gb-threshold)<0:samples.append(a.lerp(b,(threshold-ga)/(gb-ga)))
				for point:Vector2 in samples:
					var base:=height(face.point,face.normal,point)
					var old_gap:=height(p,n,point)-base;var next_gap:=height(q,m,point)-base
					# Allow existing intentional root burial to become shallower;
					# never deepen it, or accumulate lowering into a floating prop.
					# The authored local -Y face is the prop's base, transformed
					# with its full pose. Soil receding along an embedded root's
					# side is not loss of base support. Sides still reject burial.
					if face.base and old_gap>=-CONTACT-ROUNDING and next_gap < -CONTACT-ROUNDING:return false
					if next_gap > CONTACT and next_gap > old_gap+ROUNDING:return false
	return true
