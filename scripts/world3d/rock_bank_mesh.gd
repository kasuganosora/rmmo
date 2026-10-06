extends RefCounted
## Editable, deterministic grass-topped rock faces. Geometry is native record data.
const S=preload("res://scripts/world3d/document_schema.gd")
static func defaults()->Dictionary:
	return {"height":2.5,"cap_width":4.,"side":"right","roughness":.25,"seed":1,"water_level":-1.5,"direction_mode":"normal","cap_angle":0.}
static func schema()->Dictionary:
	var p:={"id":{"type":"string","maxLength":128},"name":{"type":"string","maxLength":128},"points":{"type":"array","items":S.vector(-100000,100000),"minItems":2,"maxItems":64},"inner_heights":{"type":"array","items":S.number(-1000,1000),"minItems":2,"maxItems":64},"height":S.number(.25,12),"cap_width":S.number(.5,16),"side":{"type":"string","enum":["left","right"]},"roughness":S.number(0,.75),"seed":S.number(0,2147483647,true),"water_level":S.number(-1000,1000),"rock_material_id":{"type":"string","maxLength":512},"top_material_id":{"type":"string","maxLength":512}}
	p.inner_widths={"type":"array","items":S.number(.25,16),"minItems":2,"maxItems":64}
	p.cap_angle=S.number(-180,180)
	p.direction_mode={"type":"string","enum":["normal","fixed"]}
	return {"type":"object","properties":p,"required":[],"additionalProperties":false}
static func vec(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
static func arr(v:Vector3)->Array:return [v.x,v.y,v.z]
static func noise_source(seed_:int)->FastNoiseLite:
	var noise:=FastNoiseLite.new();noise.seed=seed_;noise.noise_type=FastNoiseLite.TYPE_SIMPLEX;noise.frequency=1.;noise.fractal_octaves=3;noise.fractal_gain=.45
	return noise
static func path_error(p:Dictionary)->String:
	if not p.has("points") or p.points.size()<2:return "至少需要两个岸顶路径点"
	if p.has("inner_heights") and p.inner_heights.size()!=p.points.size():return "内侧标高数量必须与路径点一致"
	if p.has("inner_widths") and p.inner_widths.size()!=p.points.size():return "内侧宽度数量必须与路径点一致"
	var length:=0.;var lines:Array=[];var inside:Array=[]
	for i in p.points.size()-1:
		var a:=vec(p.points[i]);var b:=vec(p.points[i+1]);var flat:=Vector2(b.x-a.x,b.z-a.z);var distance:=flat.length()
		if distance<.25:return "相邻岸线点水平间距至少 0.25 米"
		if absf(a.y-b.y)>distance*.6:return "岸顶沿线坡度过大，请增加过渡长度"
		length+=distance
		if i>0:
			var previous:=vec(p.points[i])-vec(p.points[i-1]);previous.y=0
			if previous.normalized().dot(Vector3(flat.x,0,flat.y).normalized())<.35:return "岸线转角过急，请增加过渡点"
		var normal:=Vector2(-flat.y,flat.x).normalized()*(1 if p.side=="right" else -1)
		if p.get("direction_mode","normal")=="fixed":
			var directed:=Vector2(cos(deg_to_rad(p.cap_angle)),sin(deg_to_rad(p.cap_angle)))
			if normal.dot(directed)<.15:return "固定陆侧方向与岸线相反或近乎平行"
			normal=directed
		lines.append([Vector2(a.x,a.z),Vector2(b.x,b.z)])
		inside.append([Vector2(a.x,a.z)+normal*p.get("inner_widths",[])[i] if p.has("inner_widths") else Vector2(a.x,a.z)+normal*p.cap_width,Vector2(b.x,b.z)+normal*p.get("inner_widths",[])[i+1] if p.has("inner_widths") else Vector2(b.x,b.z)+normal*p.cap_width])
	if length>256:return "单段岩岸最长 256 米，请分段制作"
	for i in lines.size():
		for j in range(i+2,lines.size()):
			for first in [lines[i],inside[i]]:
				for second in [lines[j],inside[j]]:
					if Geometry2D.segment_intersects_segment(first[0],first[1],second[0],second[1])!=null:return "岸线或内侧边界自交，请调整宽度或路径"
	var sampled:=sections({"rock_bank":p})
	var orientation:=1. if p.side=="right" else -1.
	for i in sampled.size()-1:
		var a:Vector3=sampled[i].outer;var b:Vector3=sampled[i].inner;var c:Vector3=sampled[i+1].inner;var d:Vector3=sampled[i+1].outer
		if (b-a).cross(c-a).y*orientation<=.000001 or (c-a).cross(d-a).y*orientation<=.000001:return "草顶出现折叠，请减小宽度或放缓岸线弯曲"
	return ""
static func valid(record:Dictionary)->bool:
	if not record.has("rock_bank"):return not record.has("rock_bank_materials")
	if record.get("kind")!="box":return false
	for key in ["terrain_mesh","road_mesh","channel_mesh","house_prefab","building","building_shape","tile3d","fortification","fixture"]:
		if record.has(key):return false
	if not record.rock_bank is Dictionary or not record.get("rock_bank_materials") is Dictionary:return false
	if record.rock_bank_materials.size()!=2 or not record.rock_bank_materials.has_all(["rock","top"]):return false
	var sc:=schema();sc.properties.erase("id");sc.properties.erase("name");sc.properties.erase("rock_material_id");sc.properties.erase("top_material_id")
	sc.required=defaults().keys()+["points","inner_heights"]
	return S.validate(record.rock_bank,sc).is_empty() and path_error(record.rock_bank).is_empty()
static func sections(record:Dictionary)->Array:
	var p:Dictionary=record.rock_bank;var points:Array=p.points;var result:Array=[];var distance:=0.
	var noise_source_:=noise_source(int(p.seed))
	for i in points.size()-1:
		var a:=vec(points[i]);var b:=vec(points[i+1]);var flat:=Vector3(b.x-a.x,0,b.z-a.z);var length:=flat.length();var tangent:=flat/length
		var start:=tangent;var finish:=tangent
		if i>0:
			var before:=a-vec(points[i-1]);before.y=0;start=(before.normalized()+tangent).normalized()
		if i+2<points.size():
			var after:=vec(points[i+2])-b;after.y=0;finish=(after.normalized()+tangent).normalized()
		var count:=ceili(length/.3)
		for j in range(count+1):
			if i>0 and j==0:continue
			var t:=float(j)/count;var direction:=start.lerp(finish,t).normalized();var normal:=Vector3(-direction.z,0,direction.x)*(1 if p.side=="right" else -1)
			if p.get("direction_mode","normal")=="fixed":normal=Vector3(cos(deg_to_rad(p.cap_angle)),0,sin(deg_to_rad(p.cap_angle)))
			var at:=a.lerp(b,t);var station:=distance+length*t
			var noise:float=(noise_source_.get_noise_2d(station*.28,3.7)*1.4+noise_source_.get_noise_2d(station*1.1,12.8)*.35)*p.roughness
			var width:float=lerpf(p.inner_widths[i],p.inner_widths[i+1],t) if p.has("inner_widths") else p.cap_width
			noise=clampf(noise,-p.roughness,width*.35)
			var outer:=at+normal*noise;var inner:Vector3=at+normal*width;inner.y=lerpf(p.inner_heights[i],p.inner_heights[i+1],t)
			result.append({"outer":outer,"inner":inner,"normal":normal,"station":station})
		distance+=length
	return result
static func vertices(record:Dictionary)->Array[Vector3]:
	var out:Array[Vector3]=[];var scale:=vec(record.size)
	for row:Dictionary in sections(record):
		out.append(row.outer*scale);out.append(row.inner*scale);out.append((row.outer+Vector3.DOWN*record.rock_bank.height)*scale);out.append((row.inner+Vector3.DOWN*record.rock_bank.height)*scale)
	return out
static func arrays(record:Dictionary)->Array:
	var rows:=sections(record);var p:Dictionary=record.rock_bank;var scale:=vec(record.size);var result:Array=[]
	var noise:=noise_source(int(p.seed)+31)
	for slot in 2:
		var grid:Array[Vector3]=[];var uv:Array[Vector2]=[];var colors:Array[Color]=[];var across:=8
		var tile:Array=record.rock_bank_materials["top" if slot==0 else "rock"].get("tile_size",[2,2])
		for row:Dictionary in rows:
			for j in across+1:
				var t:=float(j)/across;var at:Vector3
				if slot==0:at=row.outer.lerp(row.inner,t)
				else:
					var mass:float=noise.get_noise_2d(row.station*.47+t*.6,t*1.9)
					var cracks:float=pow(maxf(0,1.-absf(noise.get_noise_2d(row.station*.76-t*.3,t*.7))*7.),3.)
					var retreat:float=minf(Vector2(row.inner.x-row.outer.x,row.inner.z-row.outer.z).length()*.8,p.roughness*(.7+mass*.8+cracks*.8))*sin(PI*t)
					at=row.outer+Vector3.DOWN*(p.height*t)+row.normal*retreat
				grid.append(at*scale)
				uv.append(Vector2(at.x/tile[0],at.z/tile[1]) if slot==0 else Vector2(row.station/tile[0],at.y/tile[1]))
				var wet:float=1.-.22*(1.-smoothstep(p.water_level-.2,p.water_level+.45,at.y)) if slot==1 else 1.
				colors.append(Color(wet,wet,wet))
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in rows.size()-1:
			for j in across:
				var a:=i*(across+1)+j;var indices:Array=[a,a+1,a+across+2,a,a+across+2,a+across+1]
				# Godot uses clockwise front faces. Top points upward, cliff toward water.
				if (slot==0 and p.side=="right") or (slot==1 and p.side=="left"):indices.reverse()
				for index:int in indices:
					st.set_uv(uv[index]);st.set_color(colors[index]);st.add_vertex(grid[index])
		if slot==1:
			# Close both ends, the buried inland side and the underside. Native
			# cliff segments remain solid when inspected or moved independently.
			for end in [0,rows.size()-1]:
				var row:Dictionary=rows[end];var outward:Vector3=(row.outer-rows[1 if end==0 else end-1].outer).normalized()
				for j in across:
					var t0:=float(j)/across;var t1:=float(j+1)/across
					quad(st,[grid[end*(across+1)+j],grid[end*(across+1)+j+1],(row.inner+Vector3.DOWN*p.height*t1)*scale,(row.inner+Vector3.DOWN*p.height*t0)*scale],outward)
			for i in rows.size()-1:
				var a:Dictionary=rows[i];var b:Dictionary=rows[i+1]
				quad(st,[a.inner*scale,(a.inner+Vector3.DOWN*p.height)*scale,(b.inner+Vector3.DOWN*p.height)*scale,b.inner*scale],a.normal)
				quad(st,[(a.outer+Vector3.DOWN*p.height)*scale,(b.outer+Vector3.DOWN*p.height)*scale,(b.inner+Vector3.DOWN*p.height)*scale,(a.inner+Vector3.DOWN*p.height)*scale],Vector3.DOWN)
		st.generate_normals();st.index();st.generate_tangents();result.append(st.commit_to_arrays())
	return result
static func quad(st:SurfaceTool,points:Array,normal:Vector3)->void:
	var indices:Array=[0,1,2,0,2,3]
	if (points[2]-points[0]).cross(points[1]-points[0]).dot(normal)<0:indices.reverse()
	for i:int in indices:
		var at:Vector3=points[i];st.set_uv(Vector2(at.x+at.z,at.y)*.5);st.set_color(Color(.85,.85,.85));st.add_vertex(at)
static func mesh(record:Dictionary,prepared:Array=[])->ArrayMesh:
	var result:=ArrayMesh.new();var built:=arrays(record) if prepared.is_empty() else prepared;var paint=load("res://scripts/world3d/surface_materials.gd")
	for i in built.size():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,built[i]);var material:StandardMaterial3D=paint.make_material(record.rock_bank_materials["top" if i==0 else "rock"],BaseMaterial3D.CULL_BACK)
		material=material.duplicate();material.vertex_color_use_as_albedo=true
		result.surface_set_material(i,material);result.surface_set_name(i,"grass_cap" if i==0 else "rock_face")
	preload("res://scripts/world3d/ground_cpu_mesh.gd").remember(result,built)
	return result
