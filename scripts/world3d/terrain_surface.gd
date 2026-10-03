extends RefCounted
## One editable heightfield per record, with shared vertices and real open cells.
const S=preload("res://scripts/world3d/document_schema.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const MODES=["raise","lower","flatten","smooth","hole","fill","erode"]
const MAX_CELLS=64

static func fail(message: String) -> Dictionary: return {"ok":false,"error":message}
static func integer(low: int, high: int) -> Dictionary: return {"type":"integer","minimum":low,"maximum":high}
static func stroke_schema() -> Dictionary:
	return {"type":"object","properties":{"id":{"type":"string","maxLength":128},"mode":{"type":"string","enum":MODES},"points":{"type":"array","minItems":1,"maxItems":128,"items":{"type":"array","minItems":2,"maxItems":2,"items":S.number(-100000,100000)}},"radius":S.number(.25,32),"strength":S.number(.01,20),"hardness":S.number(0,1),"target_height":S.number(-1000,1000),"iterations":integer(1,32),"talus_angle":S.number(15,70),"erosion_seed":integer(0,2147483647)},"required":["id","mode","points"],"additionalProperties":false}
static func create_schema() -> Dictionary:
	return {"type":"object","properties":{"source_id":{"type":"string","maxLength":128},"name":{"type":"string","maxLength":128},"center":S.vector(-100000,100000),"width":S.number(2,256),"depth":S.number(2,256),"cell_size":S.number(.25,8),"bedrock_depth":S.number(1,100),"material_id":{"type":"string","maxLength":512}},"additionalProperties":false}
static func valid(record: Dictionary) -> bool:
	if not record.has("terrain_mesh"): return not record.has("terrain_material")
	if record.get("kind")!="box": return false
	for key in ["tile3d","building","building_shape","fixture","road_mesh","channel_mesh","road_source","fortification","waterway"]:
		if record.has(key): return false
	var schema:={"type":"object","properties":{"version":{"const":1,"type":"integer","minimum":1,"maximum":1},"columns":integer(2,MAX_CELLS),"rows":integer(2,MAX_CELLS),"floor":S.number(-100,-1),"heights":{"type":"array","minItems":9,"maxItems":4225,"items":S.number(-100,1000)},"holes":{"type":"array","minItems":4,"maxItems":4096,"items":{"type":"boolean"}}},"required":["version","columns","rows","floor","heights","holes"],"additionalProperties":false}
	if not S.validate(record.terrain_mesh,schema).is_empty(): return false
	if not S.validate(record.get("size"),S.vector(.01,100000)).is_empty(): return false
	var t: Dictionary=record.terrain_mesh
	if t.heights.size()!=(int(t.columns)+1)*(int(t.rows)+1) or t.holes.size()!=int(t.columns)*int(t.rows): return false
	for height in t.heights:
		if height<t.floor+.1: return false
	return t.holes.has(false) # Empty terrain is deleted with the ordinary object tool.

static func transform(record: Dictionary) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(record.rotation[0],record.rotation[1],record.rotation[2])*PI/180),Vector3(record.position[0],record.position[1],record.position[2]))
static func point(record: Dictionary, x: int, z: int) -> Vector3:
	var t: Dictionary=record.terrain_mesh
	return Vector3((float(x)/t.columns-.5)*record.size[0],float(t.heights[z*(int(t.columns)+1)+x])*record.size[1],(float(z)/t.rows-.5)*record.size[2])
static func solid(t: Dictionary, x: int, z: int) -> bool:
	return x>=0 and z>=0 and x<int(t.columns) and z<int(t.rows) and not t.holes[z*int(t.columns)+x]
static func cell(record: Dictionary, x: int, z: int) -> Array[Vector3]:
	return [point(record,x,z),point(record,x+1,z),point(record,x+1,z+1),point(record,x,z+1)]
static func vertices(record: Dictionary) -> Array[Vector3]:
	var result: Array[Vector3]=[]; var t: Dictionary=record.terrain_mesh
	for z in int(t.rows):
		for x in int(t.columns):
			if not solid(t,x,z): continue
			for p in cell(record,x,z): result.append(p); result.append(Vector3(p.x,t.floor*record.size[1],p.z))
	return result
static func bounds(record: Dictionary) -> AABB:
	var lo:=INF; var hi:=-INF
	for h in record.terrain_mesh.heights: lo=minf(lo,h); hi=maxf(hi,h)
	lo=minf(lo,record.terrain_mesh.floor)
	return AABB(Vector3(-record.size[0]/2,lo*record.size[1],-record.size[2]/2),Vector3(record.size[0],(hi-lo)*record.size[1],record.size[2]))
static func sample(record: Dictionary, local: Vector3, ignore_holes: bool=false) -> float:
	var t: Dictionary=record.terrain_mesh
	var u: float=(local.x/record.size[0]+.5)*t.columns; var v: float=(local.z/record.size[2]+.5)*t.rows
	if u<0 or v<0 or u>t.columns or v>t.rows: return NAN
	var x:=mini(int(u),int(t.columns)-1); var z:=mini(int(v),int(t.rows)-1)
	if not ignore_holes and not solid(t,x,z): return NAN
	var p:=cell(record,x,z); u-=x; v-=z
	return p[0].y+(p[1].y-p[0].y)*u+(p[2].y-p[1].y)*v if u>=v else p[0].y+(p[2].y-p[3].y)*u+(p[3].y-p[0].y)*v
static func normal(record: Dictionary, x: int, z: int) -> Vector3:
	var t: Dictionary=record.terrain_mesh
	var dx:=point(record,mini(x+1,t.columns),z)-point(record,maxi(x-1,0),z)
	var dz:=point(record,x,mini(z+1,t.rows))-point(record,x,maxi(z-1,0))
	return dz.cross(dx).normalized()
static func mesh(record: Dictionary, fallback: Material) -> ArrayMesh:
	var t: Dictionary=record.terrain_mesh; var result:=ArrayMesh.new()
	var material: Material=Paint.make_material(record.terrain_material,BaseMaterial3D.CULL_BACK) if record.has("terrain_material") else fallback
	if material==null: material=StandardMaterial3D.new()
	var tile: Array=record.get("terrain_material",{}).get("tile_size",[2,2]); var uv_scale:=Vector2(tile[0],tile[1])
	var top:=SurfaceTool.new(); top.begin(Mesh.PRIMITIVE_TRIANGLES); top.set_material(material)
	var sides:=SurfaceTool.new(); sides.begin(Mesh.PRIMITIVE_TRIANGLES); sides.set_material(material)
	# Each shared grid vertex used to recompute its position/normal for every
	# adjacent cell. Cache once without changing triangle order or paint signatures.
	var grid:=PackedVector3Array(); var grid_normals:=PackedVector3Array()
	var stride:=int(t.columns)+1
	for z in range(int(t.rows)+1):
		for x in stride: grid.append(point(record,x,z))
	for z in range(int(t.rows)+1):
		for x in stride:
			var dx:=grid[z*stride+mini(x+1,t.columns)]-grid[z*stride+maxi(x-1,0)]
			var dz:=grid[mini(z+1,t.rows)*stride+x]-grid[maxi(z-1,0)*stride+x]
			grid_normals.append(dz.cross(dx).normalized())
	for z in int(t.rows):
		for x in int(t.columns):
			if not solid(t,x,z): continue
			var at:=z*stride+x
			var p:=[grid[at],grid[at+1],grid[at+stride+1],grid[at+stride]]
			var normals:=[grid_normals[at],grid_normals[at+1],grid_normals[at+stride+1],grid_normals[at+stride]]
			for i in [0,1,2,0,2,3]:
				top.set_normal(normals[i]); top.set_uv(Vector2(p[i].x,p[i].z)/uv_scale); top.add_vertex(p[i])
			var bottom: Array[Vector3]=[]
			for v in p: bottom.append(Vector3(v.x,t.floor*record.size[1],v.z))
			triangle(sides,[bottom[0],bottom[2],bottom[1]],uv_scale,true)
			triangle(sides,[bottom[0],bottom[3],bottom[2]],uv_scale,true)
			var neighbors:=[Vector2i(x,z-1),Vector2i(x+1,z),Vector2i(x,z+1),Vector2i(x-1,z)]
			for i in 4:
				if solid(t,neighbors[i].x,neighbors[i].y): continue
				var j: int=(i+1)%4
				triangle(sides,[p[i],bottom[i],bottom[j]],uv_scale,false)
				triangle(sides,[p[i],bottom[j],p[j]],uv_scale,false)
	top.index(); top.generate_tangents(); top.commit(result); result.surface_set_name(0,"terrain")
	sides.index(); sides.generate_tangents(); sides.commit(result); result.surface_set_name(1,"bedrock_and_cut_edges")
	return result
static func triangle(st: SurfaceTool, points: Array, tile: Vector2, horizontal: bool) -> void:
	var n: Vector3=(points[2]-points[0]).cross(points[1]-points[0]).normalized()
	for p in points:
		st.set_normal(n); st.set_uv((Vector2(p.x,p.z) if horizontal else Vector2(p.dot(Vector3.UP.cross(n)),p.y))/tile); st.add_vertex(p)
static func weight(distance: float, radius: float, hardness: float) -> float:
	if distance>radius: return 0.0
	if hardness>=.999 or distance<=radius*hardness: return 1.0
	var v: float=(radius-distance)/(radius*(1-hardness))
	return v*v*(3-2*v)
static func stroke(record: Dictionary, args: Dictionary) -> Dictionary:
	var error:=S.validate(args,stroke_schema())
	if not error.is_empty(): return fail(error)
	if not valid(record): return fail("地形数据无效")
	if absf(record.rotation[0])>.0001 or absf(record.rotation[2])>.0001: return fail("雕刻前请将地形 X/Z 旋转恢复为 0；支持平移、Y 轴旋转和缩放")
	if args.mode=="flatten" and not args.has("target_height"): return fail("整平需要 target_height 世界高度")
	var next:=record.duplicate(true); var t: Dictionary=next.terrain_mesh
	var radius: float=args.get("radius",3.0); var strength: float=args.get("strength",.5); var hardness: float=args.get("hardness",.25)
	var inverse:=transform(record).affine_inverse(); var samples: Array[Vector2]=[]
	for i in args.points.size():
		var p:=Vector2(args.points[i][0],args.points[i][1])
		if i==0: samples.append(p); continue
		var previous:=Vector2(args.points[i-1][0],args.points[i-1][1]); var count:=ceili(previous.distance_to(p)/maxf(radius*.25,.125))
		if samples.size()+count>2048: return fail("单笔路径过长，请拆分为多笔")
		for j in range(1,count+1): samples.append(previous.lerp(p,float(j)/count))
	if args.mode=="erode": return preload("res://scripts/world3d/terrain_erosion.gd").stroke(record,args,samples)
	var touched:={}
	for world in samples:
		var local:=inverse*Vector3(world.x,record.position[1],world.y)
		if absf(local.x)>record.size[0]*.5+radius or absf(local.z)>record.size[2]*.5+radius: continue
		var old: Array=t.heights.duplicate()
		if args.mode in ["hole","fill"]:
			for z in int(t.rows):
				for x in int(t.columns):
					var p: Vector3=(point(next,x,z)+point(next,x+1,z+1))*.5
					if Vector2(p.x-local.x,p.z-local.z).length()>radius: continue
					var at: int=z*int(t.columns)+x; var hole: bool=args.mode=="hole"
					if t.holes[at]!=hole: t.holes[at]=hole; touched[at]=true
		else:
			for z in range(int(t.rows)+1):
				for x in range(int(t.columns)+1):
					var p:=point(next,x,z); var w:=weight(Vector2(p.x-local.x,p.z-local.z).length(),radius,hardness)
					if w<=0: continue
					var at: int=z*(int(t.columns)+1)+x; var height: float=old[at]
					match args.mode:
						"raise": height+=strength*w/record.size[1]
						"lower": height-=strength*w/record.size[1]
						"flatten": height=move_toward(height,(args.target_height-record.position[1])/record.size[1],strength*w/record.size[1])
						"smooth":
							var total:=0.0; var count:=0
							for dz in range(maxi(0,z-1),mini(t.rows,z+1)+1):
								for dx in range(maxi(0,x-1),mini(t.columns,x+1)+1): total+=old[dz*(int(t.columns)+1)+dx]; count+=1
							height=lerpf(height,total/count,minf(strength,1)*w)
					if height<t.floor+.1 or height>1000: return fail("笔刷超出地形底床或高度范围，请减小强度")
					height=snappedf(height,.000001)
					if is_equal_approx(height,t.heights[at]): continue
					t.heights[at]=height
					for dz in [z-1,z]:
						for dx in [x-1,x]:
							if dx>=0 and dz>=0 and dx<int(t.columns) and dz<int(t.rows): touched[dz*int(t.columns)+dx]=true
	if not t.holes.has(false): return fail("不能挖掉整块地形；请使用删除物件")
	return {"ok":true,"record":next,"cells":touched.keys(),"changed":next!=record,"samples":samples.size()}
