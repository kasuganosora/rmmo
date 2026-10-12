extends RefCounted
## Pure preparation: no document mutations until every tile has passed validation.
const T=preload("res://scripts/world3d/terrain_surface.gd")

static func connected(records:Array, seed:Dictionary)->Array:
	var result:Array=[seed]; var seen:Dictionary={str(seed.uuid):true}; var cursor:=0
	while cursor<result.size() and result.size()<=256:
		var current:Dictionary=result[cursor]; cursor+=1
		for r:Dictionary in records:
			if seen.has(str(r.uuid)) or not r.has("terrain_mesh"):continue
			if absf(r.rotation[0])>.0001 or absf(r.rotation[2])>.0001:continue
			if adjacent(current,r):seen[str(r.uuid)]=true;result.append(r)
	return result

static func prepare(records:Array, seed:Dictionary, args:Dictionary)->Dictionary:
	var sources:Array=connected(records,seed) if args.get("cross_tiles",true) else [seed]
	if sources.size()>256:return T.fail("单次跨块笔刷最多连接 256 块地形，请拆分地形组")
	var entries:Array=[];var seams:Dictionary={}
	for source:Dictionary in sources:
		var request:=args.duplicate(true);request.id=source.uuid
		var entry:=T.stroke(source,request)
		if not entry.ok:return entry
		entries.append(entry)
		var r:Dictionary=entry.record;var data:Dictionary=r.terrain_mesh;var transform:=T.transform(r)
		for z in int(data.rows)+1:
			for x in int(data.columns)+1:
				if x>0 and x<int(data.columns) and z>0 and z<int(data.rows):continue
				var at:=z*(int(data.columns)+1)+x;var p:=transform*T.point(r,x,z)
				var original:=transform*T.point(source,x,z)
				var key:=Vector3i((original*1000.).round())
				if not seams.has(key):seams[key]=[]
				seams[key].append({"entry":entry,"source":source,"at":at,"height":p.y})
	# Resolve shared samples from the same pre-stroke snapshot, once. Smoothing at
	# tile edges must not depend on document order or accumulate a second stamp.
	for bucket:Array in seams.values():
		if bucket.size()<2:continue
		var touched:=false;var total:=0.
		for vertex:Dictionary in bucket:
			touched=touched or vertex.entry.record.terrain_mesh.heights[vertex.at]!=vertex.source.terrain_mesh.heights[vertex.at]
			total+=vertex.height
		if not touched:continue
		var height:=total/bucket.size()
		for vertex:Dictionary in bucket:
			var r:Dictionary=vertex.entry.record
			r.terrain_mesh.heights[vertex.at]=(height-r.position[1])/r.size[1]
			if not T.valid(r):return T.fail("同步边界将超出相邻地形底床或高度范围，整笔取消")
	# Mixed resolutions share a piecewise-linear boundary through their common
	# knots. Fine-only samples are constrained to that curve (not independently
	# raised), so both the rendered surface and collision meet without cracks.
	for i in entries.size():
		for j in range(i+1,entries.size()):
			if not adjacent(sources[i],sources[j]):continue
			var joined:=join_edges(sources[i],sources[j],entries[i].record,entries[j].record)
			if not joined.ok:return joined
	# Partial edges and T junctions may not have enough common grid knots to
	# represent a stamp on both sides. Check the complete result, since joining a
	# later neighbour can also change a corner already used by an earlier pair.
	for i in entries.size():
		for j in range(i+1,entries.size()):
			if not adjacent(sources[i],sources[j]):continue
			var checked:=validate_edge_continuity(sources[i],sources[j],entries[i].record,entries[j].record)
			if not checked.ok:return checked
	var changed:Array=[];var count:=0
	for i in entries.size():
		var entry:Dictionary=entries[i];var source:Dictionary=sources[i];var r:Dictionary=entry.record
		entry.cells=[]
		for z in int(r.terrain_mesh.rows):
			for x in int(r.terrain_mesh.columns):
				var at:=z*int(r.terrain_mesh.columns)+x
				if r.terrain_mesh.holes[at]!=source.terrain_mesh.holes[at] or T.cell(r,x,z)!=T.cell(source,x,z):entry.cells.append(at)
		entry.changed=not entry.cells.is_empty()
		if entry.changed:changed.append(entry);count+=entry.cells.size()
	var target:Dictionary=entries[sources.find(seed)]
	return {"ok":true,"changed":not changed.is_empty(),"entries":changed,"cells":range(count),"samples":target.samples,"record":target.record}

static func adjacent(a:Dictionary,b:Dictionary)->bool:
	if not T.transform(a).basis.is_equal_approx(T.transform(b).basis):return false
	var offset:=T.transform(a).affine_inverse()*T.transform(b).origin
	var span:=Vector2(a.size[0]+b.size[0],a.size[2]+b.size[2])*.5
	return (absf(absf(offset.x)-span.x)<.001 and absf(offset.z)<span.y-.001) or (absf(absf(offset.z)-span.y)<.001 and absf(offset.x)<span.x-.001)

static func edge_vertices(r:Dictionary)->Array:
	var result:Array=[];var pose:=T.transform(r);var t:Dictionary=r.terrain_mesh
	for z in int(t.rows)+1:
		for x in int(t.columns)+1:
			if x!=0 and z!=0 and x!=int(t.columns) and z!=int(t.rows):continue
			result.append({"at":z*(int(t.columns)+1)+x,"p":pose*T.point(r,x,z)})
	return result

static func edge_height(r:Dictionary,p:Vector3)->float:
	var local:Vector3=T.transform(r).affine_inverse()*p
	var half:=Vector2(float(r.size[0]),float(r.size[2]))*.5
	if absf(local.x)>half.x+.001 or absf(local.z)>half.y+.001:return NAN
	if absf(absf(local.x)-half.x)>.001 and absf(absf(local.z)-half.y)>.001:return NAN
	# The inverse transform of a shared rotated boundary can land a few ulps
	# beyond the heightfield; use the same boundary tolerance as adjacency.
	local.x=clampf(local.x,-half.x,half.x);local.z=clampf(local.z,-half.y,half.y)
	return T.sample(r,local,true)+float(r.position[1])

static func validate_edge_continuity(a:Dictionary,b:Dictionary,na:Dictionary,nb:Dictionary)->Dictionary:
	for pair:Array in [[a,b,na,nb],[b,a,nb,na]]:
		for vertex:Dictionary in edge_vertices(pair[0]):
			var old_other:=edge_height(pair[1],vertex.p)
			if not is_finite(old_other) or absf(old_other-vertex.p.y)>.002:continue
			var next:Dictionary=pair[2]
			var height:float=next.position[1]+next.terrain_mesh.heights[vertex.at]*next.size[1]
			var next_other:=edge_height(pair[3],vertex.p)
			# Preserve a pre-existing submillimetre/rounding mismatch rather than
			# rejecting an unrelated stamp merely because the old seam was not exact.
			if not is_finite(next_other) or absf(height-next_other)>absf(vertex.p.y-old_other)+.0001:
				return T.fail("相接地形的公共格点不足以同步这笔变化；请对齐分块边界或格点后重试，整笔取消")
	return {"ok":true}

static func join_edges(a:Dictionary,b:Dictionary,na:Dictionary,nb:Dictionary)->Dictionary:
	var av:=edge_vertices(a);var bv:=edge_vertices(b);var anchors:Array=[]
	for va:Dictionary in av:
		for vb:Dictionary in bv:
			if Vector2(va.p.x,va.p.z).distance_to(Vector2(vb.p.x,vb.p.z))>.001:continue
			if absf(va.p.y-vb.p.y)>.001:continue # Never silently repair pre-existing steps.
			var ha:float=na.position[1]+na.terrain_mesh.heights[va.at]*na.size[1]
			var hb:float=nb.position[1]+nb.terrain_mesh.heights[vb.at]*nb.size[1]
			anchors.append({"p":Vector2(va.p.x,va.p.z),"y":(ha+hb)*.5,"old":va.p.y})
	if anchors.size()<2:return {"ok":true}
	var axis:Vector2=(anchors[-1].p-anchors[0].p).normalized()
	anchors.sort_custom(func(x,y):return x.p.dot(axis)<y.p.dot(axis))
	for i in anchors.size()-1:
		var start:Dictionary=anchors[i];var end:Dictionary=anchors[i+1];var delta:Vector2=end.p-start.p
		if delta.length_squared()<.000001:continue
		for pair:Array in [[av,na],[bv,nb]]:
			var next:Dictionary=pair[1]
			for v:Dictionary in pair[0]:
				var p:=Vector2(v.p.x,v.p.z);var t:float=(p-start.p).dot(delta)/delta.length_squared()
				if t<-.0001 or t>1.0001 or p.distance_to(start.p+delta*t)>.001:continue
				# Only originally continuous segments are joined.
				var other:Dictionary=b if next==na else a
				var sampled:float=edge_height(other,v.p)
				if not is_finite(sampled) or absf(sampled-v.p.y)>.002:continue
				if absf(start.y-start.old)<.00001 and absf(end.y-end.old)<.00001 and absf(next.terrain_mesh.heights[v.at]*next.size[1]+next.position[1]-v.p.y)<.00001:continue
				next.terrain_mesh.heights[v.at]=(lerpf(start.y,end.y,t)-next.position[1])/next.size[1]
	if not T.valid(na) or not T.valid(nb):return T.fail("跨格距边界同步超出地形高度范围")
	return {"ok":true}
