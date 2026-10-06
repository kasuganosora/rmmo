extends RefCounted
## Real tower rooms and a city-side ascent. Openings are absent geometry/collision.
const Data=preload("res://scripts/world3d/city_layout.gd")
var plan: RefCounted
var s: Dictionary
var routes: Array=[]
static func area(p: PackedVector2Array) -> float:
	var value:=0.0
	if p.size()<3: return value
	# Triangulate relative to a local origin using scalar doubles. Absolute
	# float32 products can reverse a small clipped triangle far from (0, 0).
	for i in range(1,p.size()-1):
		value+=(float(p[i].x)-p[0].x)*(float(p[i+1].y)-p[0].y)-(float(p[i].y)-p[0].y)*(float(p[i+1].x)-p[0].x)
	return value*.5
static func positive(p: PackedVector2Array) -> PackedVector2Array:
	if area(p)<0: p.reverse()
	return p
static func clean(p: PackedVector2Array) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for v in p:
		if result.is_empty() or result[-1].distance_to(v)>.001: result.append(v)
	if result.size()>2 and result[0].distance_to(result[-1])<.001: result.remove_at(result.size()-1)
	return positive(result)
static func bounds(p: PackedVector2Array) -> Rect2:
	var r:=Rect2(p[0],Vector2.ZERO)
	for v in p: r=r.expand(v)
	return r
static func polys(r: Dictionary) -> Array:
	var result: Array=[]; var rotation: float=-deg_to_rad(r.rotation[1]); var c:=Vector2(r.position[0],r.position[2]); var size_:=Vector2(r.size[0],r.size[2])
	var source: Array=r.get("channel_mesh",{}).get("polygons",[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]])
	for polygon in source:
		var p:=PackedVector2Array()
		for v in polygon: p.append(c+(Vector2(v[0],v[1])*size_).rotated(rotation))
		result.append(positive(p))
	return result
static func difference(source: Array,cuts: Array) -> Array:
	var result:=source.duplicate()
	for cut in cuts:
		var next: Array=[]
		for p in result:
			if not bounds(p).intersects(bounds(cut)): next.append(p); continue
			for piece in Geometry2D.clip_polygons(p,cut):
				var tidy:=clean(piece)
				if tidy.size()>=3 and absf(area(tidy))>.0001: next.append(tidy)
		result=next
	return result
func slab(id: String,source: Array,bottom: float,top: float,role: String="access_masonry") -> void:
	if source.is_empty() or top-bottom<.001: return
	var patches: Array=[]
	for p in source:
		var convex: bool=p.size()==4
		for j in p.size():
			if (p[(j+1)%p.size()]-p[j]).cross(p[(j+2)%p.size()]-p[(j+1)%p.size()])<-.000001: convex=false
		if convex: patches.append(p); continue
		var indices:=Geometry2D.triangulate_polygon(p)
		for i in range(0,indices.size(),3):
			var triangle:=positive(PackedVector2Array([p[indices[i]],p[indices[i+1]],p[indices[i+2]]]))
			if area(triangle)>.0001: patches.append(triangle)
	if patches.is_empty(): return
	# Small batches keep painting, culling, collision and save work bounded.
	# Art modules follow a continuous strip: disconnected merlons MUST stay
	# separate or the deformation would bridge the deliberately cut portal.
	var batch:=1 if role=="battlement" else 18
	for start in range(0,patches.size(),batch):
		var group: Array=patches.slice(start,start+batch); var b:=bounds(group[0])
		for p in group: b=b.merge(bounds(p))
		var c:=b.get_center(); var width:=0.0; var depth:=0.0
		# At town-scale coordinates the float32 center may round by several
		# micrometres. Measure symmetric extents from that actual stored center;
		# otherwise normalized vertices can exceed +/-0.5 and fail native save.
		for p in group:
			for v in p:
				width=maxf(width,absf(float(v.x)-float(c.x))*2.0); depth=maxf(depth,absf(float(v.y)-float(c.y))*2.0)
		var r: Dictionary=plan.box(id+"_%d"%start,Vector3(c.x,(top+bottom)*.5,c.y),Vector3(width,top-bottom,depth),0,role)
		r.channel_mesh={"uv_origin":r.position.duplicate(),"polygons":[]}
		for p in group: r.channel_mesh.polygons.append(Array(p).map(func(v):return [(float(v.x)-float(c.x))/r.size[0],(float(v.y)-float(c.y))/r.size[2]]))
static func rectangle(center: Vector2,direction: Vector2,lo: float,hi: float,width: float) -> PackedVector2Array:
	var n:=Vector2(-direction.y,direction.x)*width*.5
	return positive(PackedVector2Array([center+direction*lo-n,center+direction*hi-n,center+direction*hi+n,center+direction*lo+n]))
func inward(center: Vector2,points: Array) -> Vector2:
	if s.shape=="ellipse": return (Vector2(s.center_x,s.center_z)-center).normalized()
	var at: int=points.find(center); var direction:=Vector2.ZERO
	var side: float=(1 if area(PackedVector2Array(points))>0 else -1) if s.closed else (1 if s.interior_side=="left" else -1)
	if at>0 or s.closed:
		var tangent: Vector2=(center-points[posmod(at-1,points.size())]).normalized()
		direction+=Vector2(-tangent.y,tangent.x)*side
	if at<points.size()-1 or s.closed:
		var tangent: Vector2=(points[(at+1)%points.size()]-center).normalized()
		direction+=Vector2(-tangent.y,tangent.x)*side
	return direction.normalized()
func apply(owner: RefCounted,result: Dictionary) -> Dictionary:
	if not result.ok or not owner.settings.wall_access: return result
	plan=owner; s=plan.settings; routes=[]
	var original: Array=plan.records.duplicate(true); var towers: Array=[]; var wall_polys: Array=[]
	var radius: float=maxf(s.thickness*1.6,s.height*.6)
	for r in original:
		if r.fortification.role=="corner_tower":
			var center:=Vector2(r.position[0],r.position[2]); var polygon:=PackedVector2Array()
			for j in 32: polygon.append(center+Vector2.from_angle(TAU*j/32)*radius)
			towers.append({"record":r,"polygon":polygon})
		elif r.fortification.role=="wall": wall_polys.append_array(polys(r))
	for i in towers.size():
		for j in range(i+1,towers.size()):
			if bounds(towers[i].polygon).get_center().distance_to(bounds(towers[j].polygon).get_center())<radius*2+.5: return Data.fail("内部楼梯所需圆楼相距太近，请增加塔间距")
	var cuts: Array=towers.map(func(t):return t.polygon)
	for r in original:
		if r.has("fixture"):
			for shape in polys(r):
				for cut in cuts:
					if not Geometry2D.intersect_polygons(shape,cut).is_empty(): return Data.fail("圆楼内部楼梯占地与城门冲突，请移动城门")
	plan.records=[]
	for r in original:
		if r.fortification.part.begins_with("tower_"): continue
		if r.has("fixture") or r.fortification.role=="hinge_mount": plan.records.append(r); continue
		var source:=polys(r); var trimmed:=difference(source,cuts)
		if Data.token(source)==Data.token(trimmed): plan.records.append(r); continue
		slab(r.fortification.part+"_portal",trimmed,r.position[1]-r.size[1]*.5,r.position[1]+r.size[1]*.5)
	var points: Array=s.points.map(func(p):return Vector2(p[0],p[1]))
	for i in towers.size(): make_tower(i,towers[i],wall_polys,points,radius)
	if plan.records.size()>8192: return Data.fail("可通行城墙构件超过 8192，请缩短城墙或减少塔楼")
	result.records=plan.records; result.access_routes=routes; return result
func make_tower(index: int,tower: Dictionary,walls: Array,points: Array,radius: float) -> void:
	var record: Dictionary=tower.record; var center:=Vector2(record.position[0],record.position[2]); var inside:=inward(center,points)
	var y: float=s.base_height; var deck: float=y+s.height; var id:="access_tower_%d"%index
	var floor_offset:=.03 if s.layout_version==1 else 0.0
	var poly: PackedVector2Array=tower.polygon; var skin: Array=[]
	# New recipes get a solid foundation and a slightly raised paved floor.
	# Keep old recipes unchanged when operating their already-saved doors.
	if s.layout_version==1: slab(id+"_ground_floor",[poly],y-s.foundation,y+.03,"access_floor")
	for j in poly.size():
		var a:=poly[j]; var b:=poly[(j+1)%poly.size()]
		skin.append(positive(PackedVector2Array([a,b,center+(b-center)*(1-.55/radius),center+(a-center)*(1-.55/radius)])))
	var doorway:=rectangle(center,inside,0,radius+1,3.0)
	var holes: Array=[]; var ports: Array=[]
	for offset in [-.65,0,.65]:
		if not s.arrow_slits: break
		var direction:=(-inside).rotated(offset); var at:=center+direction*radius
		holes.append(rectangle(center,direction,radius-1,radius+1,.28)); ports.append([at.x,y+1.8,at.y])
	slab(id+"_foot",difference(skin,[doorway]),y-s.foundation,y+1.3)
	slab(id+"_loopholes",difference(skin,[doorway]+holes),y+1.3,y+2.4)
	slab(id+"_upper_wall",difference(skin,[doorway]),y+2.4,y+5+floor_offset)
	slab(id+"_head",skin,y+5+floor_offset,deck)
	var tangent:=Vector2(-inside.y,inside.x)
	var door_center:=center+inside*(radius-.25)
	for side in [-1,1]:
		var p: Vector2=door_center+tangent*side*.75
		var door: Dictionary=plan.box(id+"_door_%d"%side,Vector3(p.x,y+2.5+floor_offset,p.y),Vector3(1.46,4.95,.18),-rad_to_deg(tangent.angle()),"door")
		door.fixture={"id":"tower_entrance_%d"%index,"kind":"door","pivot":[side*.75,0,0],"angle":side*100.0,"open":s.tower_door_open}
		plan.hinges(door)
	# Cadw Conwy: internal spiral ascent and wall-walk connection. Width is
	# deliberately enlarged for the game, not a claim of a measured replica.
	var steps:=preload("res://scripts/world3d/fortification_stair_mesh.gd").spec(s.height,radius)
	var start: float=inside.angle()+.4
	var end: float=start+steps.sweep
	var stair: Dictionary=plan.box(id+"_internal_stair",Vector3(center.x,y+(s.height+1.1)*.5,center.y),Vector3(radius*2,s.height+1.1,radius*2),-rad_to_deg(start),"tower_stair")
	# Roof uses radial patches so the actual stairwell stays empty, not filled
	# by a polygon triangulator treating a hole as another solid polygon.
	var roof: Array=[]; var gap_start: float=end-steps.open_angle
	var angles: Array=[gap_start,end]
	for j in 64: angles.append(gap_start+TAU*j/64)
	angles.sort(); var unique: Array=[]
	for a in angles:
		if unique.is_empty() or absf(a-unique[-1])>.00001: unique.append(a)
	unique.append(gap_start+TAU)
	for j in unique.size()-1:
		var a: float=unique[j]; var b: float=unique[j+1]; var outer: float=steps.inner if (a+b)*.5<end else radius
		roof.append(positive(PackedVector2Array([center,center+Vector2.from_angle(a)*outer,center+Vector2.from_angle(b)*outer])))
	slab(id+"_roof",roof,deck-.25,deck,"access_floor")
	var well_guard: Array=[]
	for j in 20:
		var a: float=lerpf(gap_start,end-.15,j/20.0); var b: float=lerpf(gap_start,end-.15,(j+1)/20.0)
		well_guard.append(positive(PackedVector2Array([center+Vector2.from_angle(a)*steps.inner,center+Vector2.from_angle(a)*(steps.inner+.15),center+Vector2.from_angle(b)*(steps.inner+.15),center+Vector2.from_angle(b)*steps.inner])))
	slab(id+"_stairwell_guard",well_guard,deck,deck+1.05)
	plan.strip(id+"_stairwell_end",center+Vector2.from_angle(gap_start)*steps.inner,center+Vector2.from_angle(gap_start)*(radius-.55),deck,deck+1.05,.16,"access_masonry")
	slab(id+"_parapet",difference(skin,walls),deck,deck+.45)
	if s.battlements:
		for j in 16:
			var a: float=TAU*(j+.18)/16; var b: float=TAU*(j+.82)/16
			var patch:=positive(PackedVector2Array([center+Vector2.from_angle(a)*radius,center+Vector2.from_angle(b)*radius,center+Vector2.from_angle(b)*(radius-.55),center+Vector2.from_angle(a)*(radius-.55)]))
			slab(id+"_crenel_%d"%j,difference([patch],walls),deck+.45,deck+1.35,"battlement")
	var mid_radius: float=(steps.inner+steps.outer)*.5
	var entry:=center+inside*(radius+1.3); var bottom:=center+Vector2.from_angle(start-.12)*mid_radius; var top:=center+Vector2.from_angle(end+.15)*mid_radius
	routes.append({"tower":index,"door_id":"tower_entrance_%d"%index,"entry":[entry.x,y,entry.y],"room":[center.x,y,center.y],"deck":[center.x,deck,center.y],"entry_clearance":5.0,"stairs_bottom":[bottom.x,y,bottom.y],"stairs_top":[top.x,deck,top.y],"stair_width":2.64,"landing":3.0,"stair_layout":"internal_spiral","arrow_ports":ports,"radius":radius})
