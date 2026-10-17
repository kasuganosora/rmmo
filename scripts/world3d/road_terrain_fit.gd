extends RefCounted
## Adaptive derived road cells. Authoring graph, terrain and the 512-face cap
## stay unchanged. Only an over-budget cell is quartered; stable cells retain IDs.
const Fit=preload("res://scripts/world3d/terrain_projection.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const City=preload("res://scripts/world3d/city_layout.gd")

static func fit(records:Array,terrains:Array,offset:float=.025,top_triangle_limit:int=0)->Dictionary:
	var pending:Array=records.duplicate();var output:Array=[];var divisions:=0
	while not pending.is_empty():
		var source:Dictionary=pending.pop_front()
		var fitted:=Fit.fit(source,terrains,offset)
		if fitted.ok:
			if not Surface.valid(fitted.record):return City.fail("贴地细分产生无效道路，已取消")
			if top_triangle_limit<=0 or top_triangles(fitted.record)<=top_triangle_limit:
				output.append(fitted.record)
				continue
			# A later sculpt may turn every coplanar top triangle into its own
			# paint face. Reserve the existing override budget now, so editing
			# heights never requires replacing the persisted follower IDs.
			fitted={"ok":false,"code":"road_paint_piece_limit","error":"贴地路面默认材质超过 %d 个刷面预算，请分区规划"%top_triangle_limit}
		if fitted.get("code","") not in ["terrain_projection_piece_limit","terrain_projection_kerb_limit","road_paint_piece_limit"]:return fitted
		if minf(source.size[0],source.size[2])<=.25:return fitted
		var children:=split(source)
		if children.is_empty():return City.fail("贴地细分无法保留道路轮廓")
		if output.size()+pending.size()+children.size()>4096:return City.fail("贴地道路细分超过 4096 块，请分区规划")
		pending=children+pending;divisions+=1
	return {"ok":true,"records":output,"chunks":output.size(),"subdivisions":divisions}

static func top_triangles(record:Dictionary)->int:
	var count:=0
	for polygon:Array in record.road_mesh.polygons:count+=polygon.size()-2
	return count

static func split(record:Dictionary)->Array:
	var children:Array=[];var bins:Array=[[],[],[],[]]
	# Split the existing continuous kerb by its longitudinal reference edge.
	# Each section belongs to one quadrant, including exact boundary cases;
	# split joins have no end caps and preserve the original metre-based U.
	for kerb:Dictionary in record.road_mesh.get("kerbs",[]):
		var a:=City.vec(kerb.a[0]);var b:=City.vec(kerb.b[0]);var cuts:Array=[0.,1.]
		for axis:int in [0,2]:
			if absf(b[axis]-a[axis])<.0000001:continue
			var t:float=-a[axis]/(b[axis]-a[axis])
			if t>.000001 and t<.999999 and not cuts.any(func(v):return absf(v-t)<.000001):cuts.append(t)
		cuts.sort()
		for i in cuts.size()-1:
			var low:float=cuts[i];var high:float=cuts[i+1];var middle:=a.lerp(b,(low+high)*.5)
			# A kerb exactly on the cell axis belongs to its pavement's inward
			# side, rather than an empty neighbour with no polygon to keep it.
			var inward:=City.vec(kerb.a[5]).lerp(City.vec(kerb.b[5]),(low+high)*.5)
			if absf(middle.x)<.000001:middle.x=inward.x
			if absf(middle.z)<.000001:middle.z=inward.z
			var quadrant:int=(1 if middle.x>=0 else 0)+(2 if middle.z>=0 else 0)
			var part:=kerb.duplicate(true)
			for side:String in ["a","b"]:
				var t:float=low if side=="a" else high
				for j in 6:part[side][j]=City.xyz(City.vec(kerb.a[j]).lerp(City.vec(kerb.b[j]),t))
			part.u=kerb.u+kerb.length*low;part.length=kerb.length*(high-low)
			part.cap_a=kerb.cap_a and low==0.;part.cap_b=kerb.cap_b and high==1.
			bins[quadrant].append(part)
	for quadrant in 4:
		var shift:=Vector3((.25 if quadrant%2==1 else -.25)*record.size[0],0,(.25 if quadrant>=2 else -.25)*record.size[2])
		var grade:Array=record.road_mesh.get("grade",[0.,0.]);shift.y=grade[0]*shift.x+grade[1]*shift.z
		var span:=Vector2(record.size[0]*.5,record.size[2]*.5)
		var boundary:=Poly.rect([shift.x-span.x*.5,shift.z-span.y*.5,shift.x+span.x*.5,shift.z+span.y*.5])
		var polygons:Array=[]
		for raw:Array in record.road_mesh.polygons:
			var source:Array=raw.map(func(p):return Vector2(p[0]*record.size[0],p[1]*record.size[2]))
			var cut:=Plan.intersection(source,boundary)
			if cut.size()<3 or Poly.area(cut)<.000001:continue
			var clean:Array=[]
			for p:Vector2 in cut:
				var point:=Vector2((p.x-shift.x)/span.x,(p.y-shift.z)/span.y)
				if clean.is_empty() or point.distance_squared_to(clean[-1])>1e-12:clean.append(point)
			if clean.size()>1 and clean[0].distance_squared_to(clean[-1])<=1e-12:clean.pop_back()
			if clean.size()>=3:polygons.append(clean.map(func(p):return [p.x,p.y]))
		if polygons.is_empty():continue
		var child:=record.duplicate(true);child.position=City.xyz(City.vec(record.position)+shift)
		child.size=[span.x,record.size[1],span.y]
		child.road_source=str(record.road_source)+"_q%d"%quadrant;child.uuid=child.road_source
		child.road_mesh.polygons=polygons;child.road_mesh.uv_origin=City.xyz(City.vec(record.road_mesh.uv_origin)+shift)
		child.road_mesh.erase("kerbs")
		if not bins[quadrant].is_empty():
			child.road_mesh.kerbs=bins[quadrant]
			for part:Dictionary in child.road_mesh.kerbs:
				for side:String in ["a","b"]:
					for i in 6:part[side][i]=City.xyz(City.vec(part[side][i])-shift)
		children.append(child)
	return children
