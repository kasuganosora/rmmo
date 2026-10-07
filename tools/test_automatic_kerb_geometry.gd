extends "res://tools/test_road_plan.gd"
const Kerb=preload("res://scripts/world3d/road_kerb.gd")
func run()->void:
	var cases:={"straight":[[[-50,0,0],[50,0,0]]],"cross":[[[-60,0,0],[60,0,0]],[[0,0,-35],[0,0,35]]],"T":[[[-40,0,0],[40,0,0]],[[0,0,0],[0,0,30]]],"Y":[[[0,0,-30],[0,0,0],[25,0,30]],[[0,0,0],[-25,0,30]]],"ring":[[[-25,0,-25],[25,0,-25],[25,0,25],[-25,0,25],[-25,0,-25]]],"ramp":[[[-60,0,0],[60,6,0]]],"overpass":[[[-40,0,0],[40,0,0]],[[0,6,-40],[0,6,40]]]}
	for name_ in cases:
		var g:Dictionary=Split.split(graph(cases[name_])).graph
		if name_=="overpass":g.edges[1].kind="bridge"
		var result:=Plan.build(g,Plan.defaults().merged({"kerb_enabled":true},true));check(result.ok,name_+" exposed kerb build")
		if not result.ok:print(result);continue
		var length:=0.0;var normals:=true;var seams:=true
		for record in result.records:
			check(Surface.valid(record),name_+" serialized profile validation")
			if not record.road_mesh.has("kerbs"):continue
			var arrays:=Kerb.arrays(record)
			for normal in arrays[Mesh.ARRAY_NORMAL]:normals=normals and normal.is_finite() and normal.length()>.99
			for part in record.road_mesh.kerbs:
				length+=part.length
				var a:=Kerb.vec(part.a[0])+Data.vec(record.position);var b:=Kerb.vec(part.b[0])+Data.vec(record.position)
				if name_=="straight" and absf(a.x-b.x)<.001 and absf(a.z-b.z)>.01 and absf(a.x)<49.99:seams=false
		check(normals and seams,name_+" finite normals / no internal cell edge")
		if name_=="straight":check(absf(length-(200+4*PI))<.15,"continuous straight perimeter excludes chunk seams")
	var g:=graph([[[0,0,0],[50,0,0]]]);g.edges[0].controls=[[10,0,25],[40,0,-25]]
	var curved:=Plan.build(g,Plan.defaults().merged({"kerb_enabled":true},true));check(curved.ok,"S curve kerb");if not curved.ok:print(curved)
	var approach:=graph([[[0,0,0],[30,0,0]]])
	var portal:={"endpoints":[[0,.025,0],[-10,.025,0]],"nodes":[approach.nodes[0].id,"outside"],"width":4.0}
	var bridge:=Plan.build(approach,Plan.defaults().merged({"kerb_enabled":true},true),[portal]);check(bridge.ok,"bridge approach builds")
	if bridge.ok:
		var blocked:=false;var caps:=0
		for record in bridge.records:
			for part in record.road_mesh.get("kerbs",[]):
				var a:=Kerb.vec(part.a[0])+Data.vec(record.position);var b:=Kerb.vec(part.b[0])+Data.vec(record.position)
				if absf(a.x)<.01 and absf(b.x)<.01:blocked=true
				caps+=int(part.cap_a)+int(part.cap_b)
		check(not blocked and caps==2,"bridge entrance stays open with two finished kerb ends")
	print("test_automatic_kerb_geometry: failures=",failed);quit(1 if failed else 0)
