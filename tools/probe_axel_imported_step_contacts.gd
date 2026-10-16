extends "res://tools/review_axel_functional_building_exteriors.gd"
## Read-only headless component collision diagnosis. Does not load the town.
func closest_triangle(point:Vector3,triangle:Array)->Vector3:
	var normal:Vector3=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized()
	var projected:Vector3=point-normal*normal.dot(point-triangle[0])
	var inside:=true;var nearest:=Vector3.ZERO;var distance:=INF
	for i in 3:
		var a:Vector3=triangle[i];var b:Vector3=triangle[(i+1)%3]
		if (b-a).cross(projected-a).dot(normal)<-.000001:inside=false
		var at:=Geometry3D.get_closest_point_to_segment(point,a,b)
		if at.distance_to(point)<distance:distance=at.distance_to(point);nearest=at
	return projected if inside else nearest
func run()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FB_OUT+"/final_candidate_records.json"))
	var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FB_OUT+"/functional_building_exterior_runtime/result.json"))
	var build:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FB_OUT+"/functional_buildings_apply.json"))
	var stage:=Node3D.new();root.add_child(stage)
	var rows:Array=[]
	for key:String in ["guardhouse","church"]:
		var placement:Dictionary=build.placements.filter(func(p):return p.key==key)[0]
		var record:Dictionary=data.records.filter(func(r):return r.uuid==placement.uuid)[0]
		var source:=source_geometry(record)
		var failed:Dictionary=saved.checks.filter(func(c):return c.name=="outside closed door has support and measured capsule clearance "+key)[0]
		for sample:Dictionary in failed.details.invalid:
			if float(sample.lane)!=0.:continue
			var id:=str(sample.clearance.blocked[0].id)
			var part:Dictionary=source.parts.filter(func(p):return p.id==id)[0]
			var faces:=PackedVector3Array()
			for triangle:Array in part.triangles:faces.append_array(PackedVector3Array([triangle[0],triangle[2],triangle[1]]))
			var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();var mesh:=ConcavePolygonShape3D.new();mesh.set_faces(faces);shape.shape=mesh;body.add_child(shape);stage.add_child(body)
			for tick in 3:await physics_frame
			var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.9
			var point:=vector(sample.hit.position);var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.99);query.margin=.001
			var pairs:=stage.get_world_3d().direct_space_state.collide_shape(query,128)
			var contacts:Array=[]
			for i in range(0,pairs.size(),2):
				var row:={"pair":i/2,"a":xyz(pairs[i]),"b":xyz(pairs[i+1]),"distance_m":pairs[i].distance_to(pairs[i+1])}
				for field:String in ["a","b"]:
					var p:=vector(row[field]);var closest:=INF;var normal:=Vector3.ZERO;var nearest:=Vector3.ZERO
					for triangle:Array in part.triangles:
						var n:Vector3=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized()
						var surface:Vector3=closest_triangle(p,triangle)
						if p.distance_to(surface)<closest:closest=p.distance_to(surface);normal=n;nearest=surface
					row[field+"_source_distance_m"]=closest;row[field+"_source_normal"]=xyz(normal);row[field+"_source_point"]=xyz(nearest)
				contacts.append(row)
			rows.append({"key":key,"feet":sample.hit.position,"id":id,"source_triangles":part.triangles.size(),"pairs":contacts})
			body.queue_free();await physics_frame
	var result:={"scope":"actual source GLB single-component headless physics; final-map source and controller unchanged","rows":rows}
	var file:=FileAccess.open(FB_OUT+"/imported_step_contact_probe.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print(JSON.stringify(result));quit(0)
