extends SceneTree
const B=preload("res://scripts/world3d/building_blueprint.gd")
const P=preload("res://scripts/world3d/roof_plan.gd")
const M=preload("res://scripts/world3d/roof_mesh.gd")
var failed:=0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failed+=1; push_error(message)

func audit(p: Dictionary, label_: String) -> void:
	var plan:=B.generate(p)
	check(plan.ok,"generate "+label_+": "+str(plan.get("error","")))
	if not plan.ok: return
	check(JSON.stringify(plan)==JSON.stringify(B.generate(p)),"deterministic IDs and geometry "+label_)
	var roof: Dictionary=plan.roof_plan; var types: Dictionary={}; var area:=0.0
	for edge in roof.edges: types[edge.type]=int(types.get(edge.type,0))+1
	for face in roof.faces:
		var poly: Array=[]
		for point in face.boundary: poly.append(Vector2(point[0],point[2]))
		area+=P.area(poly)
	for r in plan.records:
		if r.get("building_shape")!="roof_prism": continue
		check(B.geometry_signature(r)==B.geometry_signature(JSON.parse_string(JSON.stringify(r))),"roof signatures survive JSON roundtrip "+r.building.part)
		check(M.valid(r),"valid convex prism "+label_+" "+r.building.part+" "+JSON.stringify(r.roof_mesh))
		var mesh:=M.mesh(r,StandardMaterial3D.new())
		var moved: Dictionary=r.duplicate(true); moved.position=[312.0,4.0,-251.0]; moved.rotation=[0,73,0]
		check(mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]==M.mesh(moved,StandardMaterial3D.new()).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV],"whole-building transform keeps local roof UVs")
		check(mesh.get_surface_count()==3,"semantic roof surfaces")
		for surface in mesh.get_surface_count():
			var arrays:=mesh.surface_get_arrays(surface)
			check(arrays[Mesh.ARRAY_TANGENT]!=null,"normal-map tangent frame")
			for normal in arrays[Mesh.ARRAY_NORMAL]: check(normal.length()>.99,"nondegenerate normals")
	# Raster sample an independent expected upper envelope, excluding real holes.
	var bounds:=Rect2(-20,-20,40,45)
	for ix in range(1,110):
		for iz in range(1,120):
			var sample:=bounds.position+Vector2(ix*.37123,iz*.36913)
			var expected: Dictionary={}
			for module in roof.modules:
				if not Geometry2D.is_point_in_polygon(sample,PackedVector2Array(P.rect(module.domain))): continue
				var y:=INF
				for plane in P.planes(module): y=minf(y,P.height(plane,sample))
				var blocked:=false
				for other in roof.modules:
					if other.eave_y>module.eave_y and Geometry2D.is_point_in_polygon(sample,PackedVector2Array(P.rect(other.rect))): blocked=true
				for hole in roof.openings:
					if hole.module==module.id and Geometry2D.is_point_in_polygon(sample,PackedVector2Array(P.rect(hole.rect))): blocked=true
				if not blocked: expected[module.eave_y]=maxf(y,expected.get(module.eave_y,-INF))
			var actual: Dictionary={}; var counts: Dictionary={}
			for face in roof.faces:
				var poly:=PackedVector2Array()
				for point in face.boundary: poly.append(Vector2(point[0],point[2]))
				if not Geometry2D.is_point_in_polygon(sample,poly): continue
				var y:=P.height(P.vec(face.plane),sample); var level: float=face.floor*plan.parameters.floor_height
				actual[level]=y; counts[level]=int(counts.get(level,0))+1
			check(actual.size()==expected.size(),"coverage/hole at %s %s"%[sample,label_])
			for level in expected:
				check(absf(actual.get(level,-10000)-expected[level])<.0001 and counts.get(level,0)==1,"one continuous surface %s %s"%[sample,label_])
	print("ROOF_CASE ",label_," faces=",roof.faces.size()," projected_area=",area," edges=",types)

func run() -> void:
	for preset in B.medieval_presets(): audit(preset.parameters,preset.id)
	for compound in ["left_wing","rear_wing","courtyard"]:
		audit({"layout":"townhouse","width":14.0,"depth":16.0,"roof_axis":"width" if compound!="left_wing" else "depth","compound":compound,"annex_floors":2,"chimney":false,"dormers":0},compound+"_same_height")
	for style in ["hip","shed"]:
		audit({"layout":"townhouse","roof":style},style)
	audit({"layout":"standard","roof":"flat"},"flat")
	audit({"layout":"townhouse","width":14.0,"depth":16.0,"floors":1,"compound":"courtyard","roof_axis":"width","chimney":false},"single_storey_courtyard")
	var old:=B.instance_parameters({"version":6,"parameters":{"layout":"townhouse"}})
	check(old.roof_solver=="legacy" and not B.generate(old).has("roof_plan"),"V6 remains legacy on edit")
	check(not B.generate({"layout":"townhouse","roof":"hip","dormers":1}).ok,"unsupported opening explicitly rejected")
	var sample: Dictionary=B.generate({}).records.filter(func(r):return r.get("building_shape")=="roof_prism")[0].duplicate(true)
	var corrupt: Dictionary=sample.duplicate(true); corrupt.roof_mesh.polygon[0][0]=INF
	check(not M.valid(corrupt),"nonfinite geometry rejected")
	corrupt=sample.duplicate(true); corrupt.roof_mesh.extrusion=[0,0,0]
	check(not M.valid(corrupt),"zero thickness rejected")
	corrupt=sample.duplicate(true); corrupt.roof_mesh.polygon[1]=corrupt.roof_mesh.polygon[0]
	# Repeated vertices must not be accepted from saved or detached objects.
	check(not M.valid(corrupt),"duplicate polygon vertices rejected")
	var rng:=RandomNumberGenerator.new(); rng.seed=7319; var accepted:=0
	for i in 100:
		var params:={"layout":"townhouse","width":rng.randf_range(8,21),"depth":rng.randf_range(14,22),"roof_pitch":rng.randf_range(25,55),"roof_axis":"width" if i%2 else "depth","compound":["none","left_wing","rear_wing","courtyard"][i%4],"annex_floors":1 if i%3 else 2,"annex_width":rng.randf_range(3,5),"annex_depth":rng.randf_range(4,8),"chimney":i%2==0}
		var plan:=B.generate(params)
		if not plan.ok: continue # Explicit dimension/attachment diagnoses are valid outcomes.
		accepted+=1
		for record in plan.records:
			if record.get("building_shape")=="roof_prism": check(M.valid(record),"random metric roof prism "+str(i)+" "+record.building.part)
	check(accepted>50,"random dimensional cases exercise the solver")
	print("ROOF_RANDOM accepted=",accepted," diagnosed=",100-accepted)
	print("ROOF_PLAN_FINISHED failures=",failed); quit(1 if failed else 0)
