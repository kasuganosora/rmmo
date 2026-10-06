extends "res://tools/test_medieval_town_curves.gd"
func run() -> void:
	var spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/medieval_town_layout.json"))
	var curve:=River.new(); curve.setup(spec)
	check(curve.ribbon.get("ok",false),"valid C2 centreline and non-folding offset banks")
	if not curve.ribbon.get("ok",false): quit(1); return
	var r: Dictionary=curve.ribbon; var width_error:=0.; var turn:=0.; var tangent:=Vector2.ZERO
	for i in r.centers.size():
		width_error=maxf(width_error,absf(r.left[i].distance_to(r.right[i])-40.))
		if i>0:
			var direction: Vector2=(r.centers[i]-r.centers[i-1]).normalized()
			if i>1: turn=maxf(turn,absf(rad_to_deg(tangent.angle_to(direction))))
			tangent=direction
	check(width_error<.0002,"40m measured along the river normal: "+str(width_error))
	check(turn<2. and r.minimum_radius>60.,"no sudden turns; minimum radius "+str(r.minimum_radius)+"m, adjacent tangent change "+str(turn)+" degrees")
	if "--curve-only" in OS.get_cmdline_user_args(): quit(1 if failed else 0); return
	var candidate:="D:/code/rmmo_runtime/cache/world3d/medieval_town_ribbon/map.gltf"
	var doc=Doc.open_file(candidate)
	check(doc!=null,"load actual ribbon candidate")
	if doc==null: quit(1); return
	var roads:=City.analyze(doc.map_meta.editor_layout.roads); var crossings: Array=[]
	for edge in doc.map_meta.editor_layout.roads.edges:
		if edge.kind=="bridge": continue
		for point in roads.paths[edge.id]:
			if curve.signed_distance(Vector2(point.x,point.z))<float(edge.width_start)*.5:
				crossings.append(edge.name); break
	check(crossings.is_empty(),"new water avoids ground streets outside the five bridges: "+JSON.stringify(crossings))
	var low:=INF; var high:=0.; var shoreline:=0.
	for i in range(0,r.centers.size(),5):
		var c: Vector2=r.centers[i]; var normal: Vector2=r.normals[i]
		if absf(c.y)>650.: continue
		var edges: Array=[]
		for side in [-1.,1.]:
			var a:=0.; var b:=40.
			for step in 14:
				var mid: float=(a+b)*.5; var p: Vector2=c+normal*mid*side
				if sample_height(doc,p)> -1.5: b=mid
				else: a=mid
			edges.append((a+b)*.5)
			shoreline=maxf(shoreline,absf((a+b)*.5-20.))
		low=minf(low,edges[0]+edges[1]); high=maxf(high,edges[0]+edges[1])
	check(shoreline<.5 and low>39. and high<41.,"actual terrain waterline width %.3f .. %.3f m; bank interpolation error %.3f m"%[low,high,shoreline])
	var seam:=0.
	for z in 7:
		for x in 7:
			var h: Array=doc._find("town_terrain_%d_%d"%[x,z]).terrain_mesh.heights
			if x<6:
				var other: Array=doc._find("town_terrain_%d_%d"%[x+1,z]).terrain_mesh.heights
				for i in 65: seam=maxf(seam,absf(h[i*65+64]-other[i*65]))
			if z<6:
				var other: Array=doc._find("town_terrain_%d_%d"%[x,z+1]).terrain_mesh.heights
				for i in 65: seam=maxf(seam,absf(h[64*65+i]-other[i]))
	check(seam<.000001,"all shared terrain heights remain identical")
	var outside:=false
	for record in doc.records:
		for polygon in record.get("channel_mesh",{}).get("polygons",[]):
			for p in polygon:
				outside=outside or absf(record.position[0]+p[0]*record.size[0])>700.001 or absf(record.position[2]+p[1]*record.size[2])>700.001
	check(not outside,"water geometry stays inside map bounds")
	var report:={"failures":failed,"candidate_sha256":FileAccess.get_sha256(candidate),"width_m":40.,"analytic_width_error":width_error,"minimum_radius_m":r.minimum_radius,"max_tangent_step_degrees":turn,"actual_width_min_m":low,"actual_width_max_m":high,"shoreline_error_m":shoreline,"terrain_seam_error_m":seam}
	var f:=FileAccess.open("D:/code/rmmo_runtime/review_artifacts/medieval_town_ribbon/geometry_result.json",FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close(); quit(1 if failed else 0)
