extends RefCounted
## Solid wall cells, including real apertures. Used only while authoring/repairing.
const EPS:=.0001
static func vec(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])

static func solids(records:Array)->Array:
	var result:Array=[]
	for record:Dictionary in records:
		if record.get("building_shape")!="wall_grid" or not vec(record.rotation).is_zero_approx():continue
		var g:Dictionary=record.wall_grid;var size:=vec(record.size);var start:=vec(record.position)-size/2
		var axis:=0 if g.axis=="x" else 2;var nx:int=g.u.size()-1
		for j in g.v.size()-1:
			for i in nx:
				if not g.cells[j*nx+i]:continue
				var low:=start;var span:=size
				low[axis]+=float(g.u[i])*size[axis];span[axis]=(float(g.u[i+1])-g.u[i])*size[axis]
				low.y+=float(g.v[j])*size.y;span.y=(float(g.v[j+1])-g.v[j])*size.y
				result.append({"bounds":AABB(low,span),"floor":record.building.floor})
	return result

static func cuts(solids_:Array,axis:int,plane:float,floor_:int,area:Rect2)->Array:
	var result:Array=[];var u:=(axis+1)%3;var v:=(axis+2)%3
	for row:Dictionary in solids_:
		if row.floor!=floor_:continue
		var b:AABB=row.bounds
		if plane<b.position[axis]-EPS or plane>b.end[axis]+EPS:continue
		var cut:=Rect2(Vector2(b.position[u],b.position[v]),Vector2(b.size[u],b.size[v]))
		var overlap:=cut.intersection(area)
		if overlap.size.x>EPS and overlap.size.y>EPS:result.append(cut)
	return result
