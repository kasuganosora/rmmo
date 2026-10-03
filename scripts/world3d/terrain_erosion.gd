extends RefCounted
## Bounded, conservative thermal relaxation. Runs only when an editor stroke commits.
## The heightfield (and therefore its collision) is the result; no runtime simulation.
const MAX_WORK=250000
const DIRECTIONS=[Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(-1,1)]

static func stroke(record: Dictionary,args: Dictionary,samples: Array[Vector2]) -> Dictionary:
	var next:=record.duplicate(true); var t: Dictionary=next.terrain_mesh
	var cols:=int(t.columns); var rows:=int(t.rows); var stride:=cols+1
	var iterations:=int(args.get("iterations",8))
	var sx: float=record.size[0]/cols; var sz: float=record.size[2]/rows; var sy: float=record.size[1]
	var radius: float=args.get("radius",3.); var hardness: float=args.get("hardness",.25)
	var budget: float=args.get("strength",.5)/iterations/sy
	var threshold:=tan(deg_to_rad(float(args.get("talus_angle",35.))))/sy
	var world:=Transform3D(Basis.from_euler(Vector3(record.rotation[0],record.rotation[1],record.rotation[2])*PI/180),Vector3(record.position[0],record.position[1],record.position[2]))
	var inverse:=world.affine_inverse(); var noise:=FastNoiseLite.new()
	noise.seed=int(args.get("erosion_seed",0)); noise.frequency=.45
	var regions: Array=[]; var work:=0
	for sample in samples:
		var center:=inverse*Vector3(sample.x,record.position[1],sample.y)
		var region:=Vector4i(maxi(1,ceili((center.x-radius+record.size[0]*.5)/sx)),maxi(1,ceili((center.z-radius+record.size[2]*.5)/sz)),mini(cols-1,floori((center.x+radius+record.size[0]*.5)/sx)),mini(rows-1,floori((center.z+radius+record.size[2]*.5)/sz)))
		work+=maxi(0,region.z-region.x+1)*maxi(0,region.w-region.y+1)*iterations
		regions.append([center,region])
	if work>MAX_WORK:
		return {"ok":false,"error":"风化笔画计算量过大，请缩短路径、减小半径或减少迭代次数"}
	var mobility:=PackedFloat64Array(); mobility.resize(t.heights.size()); mobility.fill(-1.)
	var heights:=PackedFloat64Array(t.heights)
	for entry in regions:
		var center: Vector3=entry[0]; var region: Vector4i=entry[1]
		var weights:=PackedFloat64Array(); weights.resize(heights.size())
		var edges: Array=[]; var active: Array[int]=[]
		for z in range(region.y,region.w+1):
			for x in range(region.x,region.z+1):
				var at:=z*stride+x
				var d:=Vector2(x*sx-record.size[0]*.5-center.x,z*sz-record.size[2]*.5-center.z).length()
				if d>=radius: continue
				if mobility[at]<0:
					# Pin patch boundaries and all vertices bordering a hole.
					mobility[at]=0.
					if not (t.holes[(z-1)*cols+x-1] or t.holes[(z-1)*cols+x] or t.holes[z*cols+x-1] or t.holes[z*cols+x]):
						var p:=world*Vector3(x*sx-record.size[0]*.5,0,z*sz-record.size[2]*.5)
						mobility[at]=clampf(.72+noise.get_noise_2d(p.x,p.z)*.55,.35,1.)
				if mobility[at]<=0: continue
				var w:=1. if hardness>=.999 or d<=radius*hardness else smoothstep(0.,1.,(radius-d)/(radius*(1.-hardness)))
				weights[at]=w*mobility[at]; active.append(at)
		for at in active:
			var x:=at%stride; var z:=at/stride
			for direction in DIRECTIONS:
				var dx: int=x+direction.x; var dz: int=z+direction.y
				if dx<=0 or dx>=cols or dz>=rows: continue
				var other:=dz*stride+dx
				if weights[other]<=0: continue
				var distance:=Vector2(direction.x*sx,direction.y*sz).length()
				edges.append([at,other,threshold*distance,minf(weights[at],weights[other])])
		for iteration in iterations:
			var flux:=PackedFloat64Array(); flux.resize(edges.size())
			var outgoing:=PackedFloat64Array(); outgoing.resize(heights.size())
			for i in edges.size():
				var edge: Array=edges[i]; var difference: float=heights[edge[0]]-heights[edge[1]]
				var amount: float=maxf(0.,absf(difference)-edge[2])*.125*edge[3]
				flux[i]=amount*signf(difference)
				outgoing[edge[0] if difference>0 else edge[1]]+=amount
			var delta:=PackedFloat64Array(); delta.resize(heights.size())
			for i in edges.size():
				if flux[i]==0: continue
				var edge: Array=edges[i]; var donor: int=edge[0] if flux[i]>0 else edge[1]
				var available:=maxf(0.,heights[donor]-float(t.floor)-.1)
				var amount:=flux[i]*minf(1.,minf(budget*weights[donor],available)/outgoing[donor])
				delta[edge[0]]-=amount; delta[edge[1]]+=amount
			for at in active: heights[at]+=delta[at]
	var touched:={}
	for at in heights.size():
		if absf(heights[at]-float(t.heights[at]))<.000000001: continue
		t.heights[at]=heights[at]
		var x:=at%stride; var z:=at/stride
		for dz in [z-1,z]:
			for dx in [x-1,x]: touched[dz*cols+dx]=true
	return {"ok":true,"record":next,"cells":touched.keys(),"changed":not touched.is_empty(),"samples":samples.size()}
