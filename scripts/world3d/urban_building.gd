extends "res://scripts/world3d/building_geometry.gd"
## One family layout per floor; the shared stair core also reaches the roof terrace.
const FLIGHT_W := 1.4
const CORE_W := 3.2
const TREAD := .28

static func fail(message: String) -> Dictionary: return {"ok":false,"error":message}

static func generate(p: Dictionary) -> Dictionary:
	if p.template not in ["house","shop"]: return fail("城中村布局支持家庭住宅或底商住宅")
	if p.roof!="flat": return fail("城中村自建房使用可到达的平屋顶")
	if p.compound!="none" or p.jetty!=0: return fail("城中村布局暂不组合中世纪翼楼或挑层，请使用阳台参数")
	if p.balcony=="corner" and p.right_wall=="party": return fail("转角阳台需要开放右侧外墙")
	var w: float=p.width; var d: float=p.depth; var h: float=p.floor_height; var levels: int=p.floors
	if w<8.5: return fail("家庭自建房至少宽 8.5 米，以容纳房间、通道与折返楼梯")
	var left := -w/2+WALL; var right := w/2-WALL; var front := -d/2+WALL; var back := d/2-WALL
	var sx := right-CORE_W; var partition := sx-1.8; var hall_x := (partition+WALL/2+sx-WALL/2)/2
	var steps := ceili(h/2/.17); var run := steps*TREAD; var z1 := back-1.5; var z0 := z1-run; var split := z0-1.7
	if split-front<2.8: return fail("客厅与楼梯平台空间不足，请增加进深或降低层高")
	var bedroom_depth: float = (d-2*WALL-5.0-(p.bedrooms+1)*WALL)/p.bedrooms
	if bedroom_depth<2.6: return fail("卧室、厨房和卫浴放不下，请增加进深或减少卧室数")
	var colors := {"wall":[.88,.9,.88],"trim":[.62,.66,.65],"floor":[.63,.57,.49],"roof":[.55,.56,.54],"glass":[.27,.44,.48],"metal":[.38,.43,.44],"canopy":[.2,.61,.72],"cap":[.58,.21,.2]}
	if p.facade_color=="cream": colors.wall=[.9,.85,.66]; colors.cap=[.58,.36,.14]
	elif p.facade_color=="rose": colors.wall=[.82,.66,.62]; colors.cap=[.49,.23,.21]
	elif p.facade_color=="green": colors.wall=[.72,.83,.74]; colors.cap=[.2,.4,.28]
	for c in 3: colors.wall[c]=clampf(colors.wall[c]+(int(p.seed)%5-2)*.009,0,1)
	var plan := {"ok":true,"version":3,"parameters":p,"records":[],"rooms":[],"openings":[],"stairs":[],"routes":[],"terraces":[],"service_zones":[],"entrance":[hall_x,0,-d/2-1],"size":[w,levels*h+2.8,d]}
	for f in levels:
		var y := f*h; var prefix := "f%d/"%f
		floor_slab(plan,prefix,w,d,sx,z0,y,f,colors.floor)
		var west: Array=[]; var interior: Array=[]; var cursor := front
		var segments: Array=[]
		if f==0 and p.template=="shop":
			segments.append({"id":"shop","name":"店铺","depth":p.bedrooms*bedroom_depth+(p.bedrooms-1)*WALL})
		else:
			for b in p.bedrooms: segments.append({"id":"bedroom%d"%b,"name":"卧室 %d"%(b+1),"depth":bedroom_depth})
		segments.append_array([{"id":"kitchen","name":"厨房","depth":2.8},{"id":"bathroom","name":"卫浴","depth":2.2}])
		for index in segments.size():
			var segment: Dictionary=segments[index]; var end: float=cursor+segment.depth; var id: String=prefix+segment.id
			room(plan,id,segment.name,f,[left,cursor,partition-WALL/2,end],y)
			interior.append(opening(segment.id,(cursor+end)/2,"door",id))
			if p.left_wall=="open": west.append(opening(segment.id,(cursor+end)/2,"window",id,.8 if segment.id=="bathroom" else 1.3))
			if index<segments.size()-1: wall(plan,prefix+"partition/"+segment.id,"x",end+WALL/2,left,partition-WALL/2,y,h-SLAB,[],colors,f)
			if segment.id in ["kitchen","bathroom"]: plan.service_zones.append({"room":id,"floor":f,"side":"west","center":[left+.3,y,(cursor+end)/2]})
			cursor=end+WALL
		room(plan,prefix+"living","起居 / 接待" if f==0 and p.template=="shop" else "客餐厅",f,[sx,front,right,split],y)
		room(plan,prefix+"hall","家庭通道",f,[partition+WALL/2,front,sx-WALL/2,back],y)
		# Partitions meet the underside of the next slab, avoiding coplanar roof seams.
		wall(plan,prefix+"interior","z",partition,front,back,y,h-SLAB,interior,colors,f)
		wall(plan,prefix+"living_partition","z",sx-WALL/2,front,split,y,h-SLAB,[opening("living_door",(front+split)/2,"door",prefix+"living")],colors,f)
		var front_left: String=prefix+("shop" if f==0 and p.template=="shop" else "bedroom0")
		var north := [opening("front_left",(left+partition-WALL/2)/2,"door" if f==0 and p.template=="shop" else "window",front_left,minf(3.0,partition-left-.4) if f==0 and p.template=="shop" else 1.5),
			opening("entrance" if f==0 else "balcony_door",hall_x,"door" if f==0 or p.balcony!="none" else "window",prefix+"hall"),opening("living_window",(sx+right)/2,"window",prefix+"living",1.5)]
		var east: Array=[]
		if p.right_wall=="open": east.append(opening("living_side",(front+split)/2,"door" if f>0 and p.balcony=="corner" else "window",prefix+"living"))
		var south := [opening("bathroom_window",(left+partition-WALL/2)/2,"window",prefix+"bathroom",.8),opening("hall_window",hall_x,"window",prefix+"hall",.8)]
		var stair_window := opening("stair_window",sx+CORE_W/2,"window",prefix+"hall",1.2); stair_window.bottom=h-.8; stair_window.height=.5; south.append(stair_window)
		wall(plan,prefix+"west","z",-w/2+WALL/2,-d/2,d/2,y,h,west,colors,f)
		wall(plan,prefix+"east","z",w/2-WALL/2,-d/2,d/2,y,h,east,colors,f)
		wall(plan,prefix+"north","x",-d/2+WALL/2,left,right,y,h,north,colors,f)
		wall(plan,prefix+"south","x",d/2-WALL/2,left,right,y,h,south,colors,f)
		facade_bands(plan,prefix,w,d,y,h,colors,f)
		staircase(plan,prefix,sx,z0,z1,y,h,steps,colors,f)
		if f>0 and p.balcony!="none": balcony(plan,prefix,w,d,split,y,p,colors,f)
	var roof_y := levels*h
	floor_slab(plan,"roof/",w,d,sx,z0,roof_y,levels,colors.roof)
	room(plan,"roof/terrace","屋顶露台",levels,[left+.3,-d/2+.4,sx-.5,d/2-.4],roof_y)
	plan.terraces.append({"id":"roof/terrace","floor":levels,"bounds":[-w/2,-d/2,w/2,d/2],"center":[hall_x,roof_y,0]})
	# The stair headhouse has a real side exit onto the roof, with the same shaft opening.
	# Leave turn clearance on both sides of the exit, including navigation voxel erosion.
	var head_front := z0-2.1
	wall(plan,"roof/headhouse/west","z",sx-WALL/2,head_front,d/2,roof_y,2.6,[opening("roof_exit",z0-1.05,"door","roof/terrace",1.5)],colors,levels)
	wall(plan,"roof/headhouse/east","z",w/2-WALL/2,head_front,d/2,roof_y,2.6,[],colors,levels)
	wall(plan,"roof/headhouse/north","x",head_front,sx-WALL,w/2,roof_y,2.6,[],colors,levels)
	wall(plan,"roof/headhouse/south","x",d/2-WALL/2,sx-WALL,w/2,roof_y,2.6,[],colors,levels)
	box(plan,"roof/headhouse/ceiling",Vector3((sx-WALL+w/2)/2,roof_y+2.66,(head_front+d/2)/2),Vector3(w/2-sx+WALL,.12,d/2-head_front+.1),colors.cap,levels,"roof")
	# Guard the unoccupied ascending flight at the roof level, without closing its exit landing.
	wall_box(plan,"roof/shaft_guard","x",z0+.06,sx+.78,roof_y+.5,1.6,1,.08,colors.metal,levels,"rail")
	for side in [-1,1]:
		wall_box(plan,"roof/parapet_x%d"%side,"x",side*(d/2-.08),0,roof_y+.5,w,1,.16,colors.wall,levels,"parapet")
		wall_box(plan,"roof/parapet_z%d"%side,"z",side*(w/2-.08),0,roof_y+.5,d,1,.16,colors.wall,levels,"parapet")
		wall_box(plan,"roof/cap_x%d"%side,"x",side*(d/2-.08),0,roof_y+1.04,w+.05,.1,.22,colors.cap,levels,"trim")
		wall_box(plan,"roof/cap_z%d"%side,"z",side*(w/2-.08),0,roof_y+1.04,d+.05,.1,.22,colors.cap,levels,"trim")
	if p.roof_canopy: canopy(plan,"roof/canopy",[left+.35,front+.35,partition-.35,front+2.9],roof_y,colors,levels,true)
	if p.roof_tank:
		var at := Vector3(left+1.1,roof_y+.22,back-1.1)
		box(plan,"roof/tank_base",at,Vector3(1.5,.44,1.5),colors.trim,levels,"equipment")
		box(plan,"roof/tank",at+Vector3(0,.9,0),Vector3(1.3,1.4,1.3),[.68,.72,.73],levels,"equipment"); plan.records.back().building_shape="cylinder"
		box(plan,"roof/tank_lid",at+Vector3(0,1.65,0),Vector3(.5,.1,.5),colors.metal,levels,"equipment"); plan.records.back().building_shape="cylinder"
		box(plan,"roof/tank_pipe",Vector3(left+.25,roof_y+.3,back-1.1),Vector3(.09,.6,.09),colors.metal,levels,"equipment")
	if p.ground_canopy: canopy(plan,"entry_canopy",[-w/2,-d/2-.9,w/2,-d/2+.1],0,colors,0,false)
	for record in plan.records: record.building.floor_y=int(record.building.floor)*h
	return plan

static func room(plan: Dictionary, id: String, title: String, f: int, bounds: Array, y: float) -> void:
	plan.rooms.append({"id":id,"name":title,"floor":f,"bounds":bounds,"center":[(bounds[0]+bounds[2])/2,y,(bounds[1]+bounds[3])/2]})

static func opening(id: String, u: float, type: String, room_id: String, width := 1.3) -> Dictionary:
	return {"id":id,"u":u,"bottom":0.0 if type=="door" else 1.0,"width":width,"height":2.2 if type=="door" else 1.3,"type":type,"room":room_id}

static func floor_slab(plan: Dictionary, prefix: String, w: float, d: float, sx: float, z0: float, y: float, f: int, color: Array) -> void:
	if f==0: slab(plan,prefix+"floor",-w/2,w/2,-d/2,d/2,y+.02,color,f); return
	slab(plan,prefix+"floor/left",-w/2,sx-.06,-d/2,d/2,y,color,f)
	slab(plan,prefix+"floor/front",sx-.06,w/2,-d/2,z0+.03,y,color,f)
	slab(plan,prefix+"floor/back",sx-.06,w/2,d/2-.12,d/2,y,color,f)
	slab(plan,prefix+"floor/right",w/2-.12,w/2,z0+.03,d/2-.12,y,color,f)

static func staircase(plan: Dictionary, prefix: String, sx: float, z0: float, z1: float, y: float, h: float, steps: int, colors: Dictionary, f: int) -> void:
	var half := h/2; var length := z1-z0
	slab(plan,prefix+"stair/turn",sx,sx+CORE_W,z1,z1+1.5,y+half,colors.floor,f)
	# The hallway edge and half landing need their own guards above the lower flight.
	if f>0: rail(plan,prefix+"stair/hall_guard","z",sx-.025,z0+.08,z1+1.5,y,colors,f)
	rail(plan,prefix+"stair/turn_guard","z",sx+.02,z1,z1+1.5,y+half,colors,f)
	for flight in 2:
		var x := sx+.05+flight*1.7; var direction := 1 if flight==0 else -1
		var start := z0 if flight==0 else z1; var base := y+flight*half
		var bottom := Vector3(x+FLIGHT_W/2,base,start-direction*.6)
		var top := Vector3(x+FLIGHT_W/2,base+half,(z1 if flight==0 else z0)+direction*.6)
		plan.stairs.append({"floor":f,"flight":flight,"hole":[sx-.06,z0+.03,sx+CORE_W+.08,z1+1.5],"bottom":arr(bottom),"top":arr(top),"direction":[0,0,direction]})
		for step in steps:
			var rise := half*(step+1)/steps; var z := start+direction*(step+.5)*length/steps
			var key := prefix+"stair/%d/step%d"%[flight,step]
			box(plan,key,Vector3(x+FLIGHT_W/2,base+rise-.07,z),Vector3(FLIGHT_W,.14,length/steps+.004),colors.floor,f,"stairs")
			for side in [-1,1]: box(plan,key+"/rail%d"%side,Vector3(x+FLIGHT_W/2+side*(FLIGHT_W/2+.02),base+rise+.5,z),Vector3(.07,1,length/steps),colors.metal,f,"rail")
		if flight==1: slab(plan,prefix+"stair/top_landing",x-.03,x+FLIGHT_W+.03,z0-.2,z0+.15,y+h,colors.floor,f+1)

static func rail(plan: Dictionary, key: String, axis: String, fixed: float, start: float, end: float, y: float, colors: Dictionary, f: int) -> void:
	for height in [.25,.65,1.05]: wall_box(plan,key+"/bar%d"%int(height*100),axis,fixed,(start+end)/2,y+height,end-start,.065,.065,colors.metal,f,"rail")
	var count := maxi(1,ceili((end-start)/1.3))
	for i in count+1: wall_box(plan,key+"/post%d"%i,axis,fixed,lerpf(start,end,float(i)/count),y+.55,.065,1.1,.065,colors.metal,f,"rail")

static func balcony(plan: Dictionary, prefix: String, w: float, d: float, split: float, y: float, p: Dictionary, colors: Dictionary, f: int) -> void:
	var depth: float=p.balcony_depth; var edge := -d/2-depth; var right: float=w/2+(depth if p.balcony=="corner" else 0)
	slab(plan,prefix+"balcony/front",-w/2,right,edge,-d/2,y,colors.floor,f)
	rail(plan,prefix+"balcony/front_rail","x",edge+.08,-w/2+.08,right-.08,y,colors,f)
	rail(plan,prefix+"balcony/left_rail","z",-w/2+.08,edge+.08,-d/2,y,colors,f)
	rail(plan,prefix+"balcony/right_rail","z",right-.08,edge+.08,split if p.balcony=="corner" else -d/2,y,colors,f)
	if p.balcony=="corner":
		slab(plan,prefix+"balcony/side",w/2,right,-d/2,split,y,colors.floor,f)
		rail(plan,prefix+"balcony/end_rail","x",split-.08,w/2,right-.08,y,colors,f)
		plan.terraces.append({"id":prefix+"balcony_side","floor":f,"bounds":[w/2,-d/2,right,split],"center":[w/2+depth/2,y,(-d/2+split)/2]})
	plan.terraces.append({"id":prefix+"balcony","floor":f,"bounds":[-w/2,edge,right,-d/2],"center":[0,y,edge+depth/2]})

static func facade_bands(plan: Dictionary, prefix: String, w: float, d: float, y: float, h: float, colors: Dictionary, f: int) -> void:
	for side in [-1,1]:
		wall_box(plan,prefix+"facade/x%d"%side,"x",side*d/2,0,y+h-.15,w+.06,.2,.06,colors.trim,f,"trim")
		wall_box(plan,prefix+"facade/z%d"%side,"z",side*w/2,0,y+h-.15,d+.06,.2,.06,colors.trim,f,"trim")
		for x in [-w/2+.1,w/2-.1]: box(plan,prefix+"facade/post%d_%d"%[side,0 if x<0 else 1],Vector3(x,y+h/2,side*d/2),Vector3(.12,h,.065),colors.trim,f,"trim")

static func canopy(plan: Dictionary, key: String, bounds: Array, y: float, colors: Dictionary, f: int, posts: bool) -> void:
	var x: float=(bounds[0]+bounds[2])/2; var z: float=(bounds[1]+bounds[3])/2
	box(plan,key+"/sheet",Vector3(x,y+2.65,z),Vector3(bounds[2]-bounds[0],.09,bounds[3]-bounds[1]),colors.canopy,f,"canopy")
	var ribs := maxi(1,ceili((bounds[2]-bounds[0])/.6))
	for i in ribs+1: box(plan,key+"/rib%d"%i,Vector3(lerpf(bounds[0],bounds[2],float(i)/ribs),y+2.71,z),Vector3(.035,.035,bounds[3]-bounds[1]),colors.trim,f,"trim")
	if posts:
		for i in 4:
			box(plan,key+"/post%d"%i,Vector3(bounds[0] if i<2 else bounds[2],y+1.3,bounds[1] if i%2==0 else bounds[3]),Vector3(.08,2.6,.08),colors.metal,f,"post")
