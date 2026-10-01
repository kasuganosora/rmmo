extends "res://scripts/world3d/building_geometry.gd"
## Narrow street houses and hall houses share rooms, wall openings and floor voids.
const STAIR_W := 1.4
const TREAD := .28

static func fail(message: String) -> Dictionary: return {"ok":false,"error":message}

static func generate(p: Dictionary) -> Dictionary:
	var w: float = p.width; var d: float = p.depth; var h: float = p.floor_height
	var levels: int = p.floors; var count: int = p.rooms_per_floor
	if p.roof!="gable": return fail("中世纪布局使用坡屋顶，请选择双坡屋顶")
	if p.layout=="hall" and (levels!=2 or count!=2 or p.jetty>0): return fail("大厅住宅使用两层、每层房间参数 2，挑空大厅不支持临街挑层")
	if p.compound!="none" and levels<2: return fail("带附属房的主屋至少两层，以保证连接屋顶净空")
	if p.compound=="left_wing" and (p.left_wall=="party" or p.annex_depth>d-2): return fail("左侧翼需要开放左墙，且翼楼进深不能超过主屋进深减 2 米")
	if p.compound=="courtyard" and w<2*p.annex_width+2.5: return fail("围院中间至少保留 2.5 米通道，请增加主屋宽度或减小翼楼宽度")
	if p.compound!="none" and p.annex_width/2*tan(deg_to_rad(p.roof_pitch))+h>=levels*h-.15: return fail("附属房屋脊高于主屋檐口，请减小附属房宽度或坡度，或增加主屋层数")
	var steps := ceili(h/.17); var run := steps*TREAD
	var stair_right := w/2-WALL-.15; var stair_left := stair_right-STAIR_W
	# Leave voxel clearance as well as capsule clearance at both turning platforms.
	var z1 := d/2-1.8; var z0 := z1-run; var split_z := z0-1.5
	var front_count := maxi(1,count-1)
	if levels>1 and (split_z-(-d/2+WALL))/front_count<2.6: return fail("前屋与楼梯平台空间不足，请增加进深、减少房间或降低层高")
	if levels==1: split_z = d/2-3.2
	var palette := {"wall":[.82,.76,.62],"trim":[.22,.12,.065],"floor":[.49,.34,.21],"roof":[.43,.17,.105],"glass":[.29,.39,.38],"stone":[.44,.43,.37],"shutter":[.29,.36,.23]}
	if p.style=="plaster": palette.wall=[.79,.8,.73]; palette.trim=[.32,.3,.25]; palette.roof=[.28,.31,.32]
	var tint := float(int(p.seed)%7-3)*.012
	for channel in 3: palette.wall[channel] = clampf(palette.wall[channel]+tint,0,1)
	var plan := {"ok":true,"version":2,"parameters":p,"records":[],"rooms":[],"openings":[],"stairs":[],"routes":[],"volumes":[],"courtyards":[],"connections":[],"entrance":[-w/2+1.2,0,-d/2-1],"size":[w,levels*h+w/2,d]}
	var annexes := annex_specs(p)
	for f in levels:
		var y := f*h; var front: float = -d/2-(float(p.jetty) if f>0 else 0.0)
		var prefix := "f%d/"%f; var start: float = split_z if p.layout=="hall" and f==1 else front
		if f==0: slab(plan,prefix+"floor",-w/2,w/2,start,d/2,y,palette.floor,f)
		else:
			slab(plan,prefix+"floor/left",-w/2,stair_left-.09,start,d/2,y,palette.floor,f)
			slab(plan,prefix+"floor/right",stair_right+.09,w/2,start,d/2,y,palette.floor,f)
			slab(plan,prefix+"floor/front",stair_left-.09,stair_right+.09,start,z0-.08,y,palette.floor,f)
			slab(plan,prefix+"floor/back",stair_left-.09,stair_right+.09,z1+.08,d/2,y,palette.floor,f)
			box(plan,prefix+"landing",Vector3((stair_left+stair_right)/2,y-SLAB/2,z1+.06),Vector3(STAIR_W+.18,SLAB,.28),palette.floor,f,"floor")
		var left_windows: Array = []; var right_windows: Array = []
		var front_windows: Array = []; var back_windows: Array = []
		var is_loft: bool = p.layout=="hall" and f==1
		if not is_loft:
			if count==1:
				room(plan,prefix+"room0","通厅",f,[-w/2+WALL,front+WALL,stair_left-.35,d/2-WALL],y)
			else:
				for r in front_count:
					var a: float = lerpf(front+WALL,split_z,float(r)/front_count)
					var b: float = lerpf(front+WALL,split_z,float(r+1)/front_count)
					var name_: String = "大厅" if p.layout=="hall" else ("店铺" if f==0 and p.template=="shop" and r==0 else ("起居室" if f==0 else "卧室 %d"%(r+1)))
					room(plan,prefix+"room%d"%r,name_,f,[-w/2+WALL,a,w/2-WALL,b],y)
					wall(plan,prefix+"partition%d"%r,"x",b,-w/2+WALL,w/2-WALL,y,h,[opening("door",-w/2+1.2,"door",prefix+"room%d"%r)],palette,f)
					left_windows.append(opening("room%d"%r,(a+b)/2,"window",prefix+"room%d"%r))
					right_windows.append(opening("room%d"%r,(a+b)/2,"window",prefix+"room%d"%r))
				room(plan,prefix+"rear",("厨房 / 后厅" if f==0 else "楼梯厅"),f,[-w/2+WALL,split_z,stair_left-.35,d/2-WALL],y)
		else:
			room(plan,prefix+"rear","楼上私室",f,[-w/2+WALL,split_z,stair_left-.35,d/2-WALL],y)
			box(plan,prefix+"gallery_guard",Vector3((-w/2+stair_left-.09)/2,y+.5,split_z),Vector3(stair_left-.09+w/2,1,.09),palette.trim,f,"rail")
		var rear_id := prefix+("room0" if count==1 else "rear")
		left_windows.append(opening("rear",(split_z+d/2-WALL)/2,"window",rear_id))
		var front_id := ("f0/room0" if is_loft else prefix+"room0")
		front_windows.append(opening("front_window",w/2-1.2,"window",front_id))
		front_windows.append(opening("entrance" if f==0 else "upper_window",-w/2+1.2,"door" if f==0 else "window",front_id))
		back_windows.append(opening("rear_window",-w/2+1.2,"window",rear_id))
		if f==0:
			if p.compound=="rear_workshop": back_windows=[opening("yard_door",0,"door",rear_id)]
			for annex in annexes:
				if annex.join=="west": left_windows.append(opening("wing_door",annex.center[1],"door",rear_id))
				elif annex.join=="south": back_windows.append(opening(annex.id+"_door",annex.center[0],"door",rear_id))
		# The main wall remains the single shared wall. Blank its windows below the attached roof.
		for annex in annexes:
			if f*h+1>=annex.roof_top: continue
			if annex.join=="west": left_windows=left_windows.filter(func(o): return o.type=="door" or absf(o.u-annex.center[1])>annex.depth/2+.75)
			elif annex.join=="south": back_windows=back_windows.filter(func(o): return o.type=="door" or absf(o.u-annex.center[0])>annex.width/2+.75)
		if p.left_wall=="party": left_windows=[]
		if p.right_wall=="party": right_windows=[]
		framed_wall(plan,prefix+"west","z",-w/2+WALL/2,front,d/2,y,h,left_windows,palette,f,p)
		framed_wall(plan,prefix+"east","z",w/2-WALL/2,front,d/2,y,h,right_windows,palette,f,p)
		framed_wall(plan,prefix+"north","x",front+WALL/2,-w/2+WALL,w/2-WALL,y,h,front_windows,palette,f,p)
		framed_wall(plan,prefix+"south","x",d/2-WALL/2,-w/2+WALL,w/2-WALL,y,h,back_windows,palette,f,p)
		if f<levels-1: staircase(plan,prefix,stair_left,stair_right,z0,z1,y,h,steps,palette,f)
		elif f>0:
			box(plan,prefix+"well/front",Vector3((stair_left+stair_right)/2,y+.5,z0-.08),Vector3(STAIR_W+.18,1,.08),palette.trim,f,"rail")
			for x in [stair_left-.09,stair_right+.09]: box(plan,prefix+"well/side%d"%(0 if x<stair_left else 1),Vector3(x,y+.5,(z0+z1)/2),Vector3(.08,1,run),palette.trim,f,"rail")
		if f==1 and p.jetty>0:
			for i in 3:
				var x: float=[-w/2+.3,0,w/2-.3][i]
				box(plan,prefix+"jetty_bracket%d"%i,Vector3(x,y-.3,-d/2-float(p.jetty)/2),Vector3(.14,.65,.14),palette.trim,f,"bracket",Vector3(-35,0,0))
	var extra_front: float = p.jetty if levels>1 else 0.0
	slab(plan,"roof/ceiling",-w/2,w/2,-d/2-extra_front,d/2,levels*h,palette.wall,levels)
	roof(plan,"roof",Vector3(0,levels*h,-extra_front/2),w,d+extra_front,p,palette,levels)
	plan.volumes.append({"rect":[-w/2,-d/2-extra_front,w/2,d/2],"top":levels*h+maxf(w,d)/2*tan(deg_to_rad(p.roof_pitch))})
	for annex in annexes: build_annex(plan,annex,p,palette)
	if p.compound=="rear_workshop":
		slab(plan,"yard/floor",-w/2,w/2,d/2,d/2+3,0,palette.stone,0)
		plan.courtyards.append([-w/2,d/2,w/2,d/2+3]); plan.connections.append({"from":"f0/room0" if count==1 else "f0/rear","to":"workshop/room","via":"yard"})
	elif p.compound=="courtyard":
		var inner: float = w/2-p.annex_width
		slab(plan,"yard/floor",-inner,inner,d/2,d/2+p.annex_depth,0,palette.stone,0)
		plan.courtyards.append([-inner,d/2,inner,d/2+p.annex_depth])
	for record in plan.records:
		record.building.floor_y = int(record.building.floor)*h
		# Keep the finished ground-floor surface above supporting terrain, avoiding z-fighting.
		if record.building.floor==0 and record.building.role=="floor": record.position[1]+=.02
	return plan

static func opening(id: String, u: float, type: String, room_id: String) -> Dictionary:
	return {"id":id,"u":u,"bottom":0.0 if type=="door" else 1.0,"width":1.4 if type=="door" else 1.05,"height":2.2 if type=="door" else 1.15,"type":type,"room":room_id}

static func room(plan: Dictionary, id: String, title: String, f: int, bounds: Array, y: float) -> void:
	plan.rooms.append({"id":id,"name":title,"floor":f,"bounds":bounds,"center":[(bounds[0]+bounds[2])/2,y,(bounds[1]+bounds[3])/2]})

static func framed_wall(plan: Dictionary, key: String, axis: String, fixed: float, start: float, end: float, y: float, height: float, openings: Array, colors: Dictionary, f: int, p: Dictionary) -> void:
	wall(plan,key,axis,fixed,start,end,y,height,openings,colors,f)
	wall_box(plan,key+"/beam",axis,fixed,(start+end)/2,y+height-.13,end-start,.2,WALL+.025,colors.trim,f,"beam")
	var bays := maxi(1,ceili((end-start)/float(p.bay_width)))
	for i in bays+1:
		var u := lerpf(start+.075,end-.075,float(i)/bays)
		if openings.any(func(o): return absf(u-o.u)<o.width/2+.14): continue
		wall_box(plan,key+"/post%d"%i,axis,fixed,u,y+height/2,.14,height,WALL+.025,colors.trim,f,"post")
	for i in bays:
		var u := lerpf(start,end,(i+.5)/bays)
		var length := minf((end-start)/bays*.65,.9)
		var size := Vector3(length,.105,.105) if axis=="x" else Vector3(.105,.105,length)
		var at := Vector3(u,y+height-.43,fixed) if axis=="x" else Vector3(fixed,y+height-.43,u)
		box(plan,key+"/brace%d"%i,at,size,colors.trim,f,"brace",Vector3(0,0,25) if axis=="x" else Vector3(-25,0,0))
	if p.shutters:
		for o in openings:
			if o.type!="window": continue
			# Open shutters sit outside the aperture; they never close the room's window.
			for side in [-1,1]: wall_box(plan,key+"/shutter_"+o.id+str(side),axis,fixed,o.u+side*(o.width/2+.23),y+o.bottom+o.height/2,.32,o.height,WALL+.045,colors.shutter,f,"shutter")

static func staircase(plan: Dictionary, key: String, left: float, right: float, z0: float, z1: float, y: float, h: float, steps: int, colors: Dictionary, f: int) -> void:
	plan.stairs.append({"floor":f,"hole":[left-.09,z0-.08,right+.09,z1+.08],"bottom":[(left+right)/2,y,z0-.55],"top":[(left+right)/2,y+h,z1+.6]})
	for step in steps:
		var rise := h*(step+1)/steps
		box(plan,key+"step%d"%step,Vector3((left+right)/2,y+rise-.07,z0+(step+.5)*TREAD),Vector3(STAIR_W,.14,TREAD+.004),colors.floor,f,"stairs")
		for x in [left-.04,right+.04]: box(plan,key+"rail%d_%d"%[step,0 if x<left else 1],Vector3(x,y+rise+.5,z0+(step+.5)*TREAD),Vector3(.08,1,TREAD),colors.trim,f,"rail")

static func roof(plan: Dictionary, key: String, at: Vector3, w: float, d: float, p: Dictionary, colors: Dictionary, f: int, skip_end := 0) -> void:
	var crosswise: bool = p.roof_axis=="width"
	var span := d if crosswise else w; var length := w if crosswise else d
	var pitch := deg_to_rad(p.roof_pitch); var rise := span/2*tan(pitch)
	var e: float = p.eaves; var first: int = plan.records.size()
	var over_left: float = 0 if not crosswise and p.left_wall=="party" else e
	var over_right: float = 0 if not crosswise and p.right_wall=="party" else e
	var end_left: float = 0 if crosswise and p.right_wall=="party" else e
	var end_right: float = 0 if crosswise and p.left_wall=="party" else e
	if skip_end==-1: end_left=0
	if skip_end==1: end_right=0
	for side in [-1,1]:
		var over := over_left if side<0 else over_right
		var half := span/2+over; var low := -over*tan(pitch)
		box(plan,key+"/slope%d"%side,Vector3(side*half/2,(rise+low)/2,(end_right-end_left)/2),Vector3(half/cos(pitch),.14,length+end_left+end_right),colors.roof,f,"roof",Vector3(0,0,-side*rad_to_deg(pitch)))
	box(plan,key+"/ridge",Vector3(0,rise+.035,0),Vector3(.14,.14,length+end_left+end_right),colors.trim,f,"roof")
	for side in [-1,1]:
		if side==skip_end: continue
		box(plan,key+"/gable%d"%side,Vector3(0,rise/2,side*(length/2-WALL/2)),Vector3(span,rise,WALL),colors.wall,f,"roof")
		plan.records.back().building_shape="gable"
		for slope in [-1,1]: box(plan,key+"/rafter%d_%d"%[side,slope],Vector3(slope*span/4,rise/2,side*(length/2+.015)),Vector3(span/2/cos(pitch),.13,.14),colors.trim,f,"roof",Vector3(0,0,-slope*rad_to_deg(pitch)))
	var basis := Basis(Vector3.UP,PI/2 if crosswise else 0.0)
	for index in range(first,plan.records.size()):
		var record: Dictionary = plan.records[index]
		record.position=arr(at+basis*vec(record.position)); record.rotation=arr((basis*Basis.from_euler(vec(record.rotation)*PI/180)).get_euler()*180/PI)

static func annex_specs(p: Dictionary) -> Array:
	var result: Array = []; var w: float = p.width; var d: float = p.depth
	if p.compound=="rear_workshop": result.append({"id":"workshop","center":[0,d/2+3+p.annex_depth/2],"width":p.annex_width,"depth":p.annex_depth,"join":"none"})
	elif p.compound=="left_wing": result.append({"id":"wing","center":[-w/2-p.annex_width/2+WALL/2,d/2-p.annex_depth/2],"width":p.annex_width,"depth":p.annex_depth,"join":"west"})
	elif p.compound=="courtyard":
		for side in [-1,1]: result.append({"id":"wing_left" if side<0 else "wing_right","center":[side*(w-p.annex_width)/2,d/2+p.annex_depth/2-WALL/2],"width":p.annex_width,"depth":p.annex_depth,"join":"south"})
	for a in result: a.roof_top=p.floor_height+a.width/2*tan(deg_to_rad(p.roof_pitch))
	return result

static func build_annex(plan: Dictionary, a: Dictionary, p: Dictionary, colors: Dictionary) -> void:
	var x: float = a.center[0]; var z: float = a.center[1]; var h: float = p.floor_height
	var x0: float = x-a.width/2; var x1: float = x+a.width/2; var z0: float = z-a.depth/2; var z1: float = z+a.depth/2
	var key: String = a.id; var id := key+"/room"
	room(plan,id,"作坊" if a.join=="none" else "附属房",0,[x0+WALL,z0+WALL,x1-WALL,z1-WALL],0)
	slab(plan,key+"/floor",x0,x1,z0,z1,0,colors.floor,0)
	slab(plan,key+"/ceiling",x0,x1,z0,z1,h,colors.wall,1)
	for side in ["west","east","north","south"]:
		if (side=="east" and a.join=="west") or (side=="north" and a.join=="south"): continue
		var axis := "z" if side in ["west","east"] else "x"
		var fixed: float = {"west":x0+WALL/2,"east":x1-WALL/2,"north":z0+WALL/2,"south":z1-WALL/2}[side]
		var o := opening("entry" if side=="north" else "window",z if axis=="z" else x,"door" if side=="north" else "window",id)
		framed_wall(plan,key+"/"+side,axis,fixed,z0 if axis=="z" else x0+WALL,z1 if axis=="z" else x1-WALL,0,h,[o],colors,0,p)
	var roof_parameters: Dictionary = p.duplicate(); roof_parameters.roof_axis="depth"; roof_parameters.left_wall="open"; roof_parameters.right_wall="open"
	# A side wing ends its eave at the shared wall; rear wings end their roof at it.
	if a.join=="west": roof_parameters.right_wall="party"
	roof(plan,key+"/roof",Vector3(x,h,z),a.width,a.depth,roof_parameters,colors,1,-1 if a.join=="south" else 0)
	plan.volumes.append({"rect":[x0,z0,x1,z1],"top":a.roof_top})
	if a.join!="none": plan.connections.append({"from":"f0/room0" if p.rooms_per_floor==1 else "f0/rear","to":id,"via":"wing_door" if a.join=="west" else a.id+"_door"})
