extends "res://scripts/world3d/building_geometry.gd"
## Narrow street houses and hall houses share rooms, wall openings and floor voids.
const TREAD := .28

static func fail(message: String) -> Dictionary: return {"ok":false,"error":message}

static func generate(p: Dictionary) -> Dictionary:
	var w: float = p.width; var d: float = p.depth; var h: float = p.floor_height
	var levels: int = p.floors; var count: int = p.rooms_per_floor
	if p.roof=="flat": return fail("中世纪布局使用坡屋顶，请选择双坡、四坡或单坡屋顶")
	if p.roof!="gable" and p.get("dormers",0)>0: return fail("老虎窗当前支持双坡屋顶；四坡和单坡请将数量设为 0")
	if p.annex_floors>levels: return fail("翼楼不能高于主屋")
	if p.compound=="rear_workshop" and p.annex_floors!=1: return fail("独立作坊目前只支持一层；多层请使用连通翼楼")
	if p.get("dormers",0)>0 and (w if p.roof_axis=="width" else d)<p.dormers*2.2+.8: return fail("老虎窗之间需要留出屋面，请减少数量或增加屋脊长度")
	if p.get("dormers",0)>0 and p.roof_axis=="depth" and p.left_wall=="party": return fail("邻接墙侧不能伸出老虎窗；请调整屋脊朝向或关闭老虎窗")
	if p.layout=="hall" and (levels!=2 or count!=2 or p.jetty>0): return fail("大厅住宅使用两层、每层房间参数 2，挑空大厅不支持临街挑层")
	if p.compound!="none" and levels<2 and p.roof_solver=="legacy": return fail("旧版低翼楼屋顶要求主屋至少两层；单层同高翼楼请使用统一屋面")
	if p.compound=="left_wing" and (p.left_wall=="party" or p.annex_depth>d-2): return fail("左侧翼需要开放左墙，且翼楼进深不能超过主屋进深减 2 米")
	if p.compound=="courtyard" and w<2*p.annex_width+2.5: return fail("围院中间至少保留 2.5 米通道，请增加主屋宽度或减小翼楼宽度")
	if p.compound!="none" and p.annex_floors<levels and annex_rise(p)+p.annex_floors*h>=levels*h-.15: return fail("低翼楼屋脊高于主屋檐口，请减小附属房宽度或坡度，或增加主屋层数")
	var steps := ceili(h/.17); steps+=steps%2
	var folded: bool=p.get("stair_layout","straight")=="switchback"
	var run: float=steps*TREAD if not folded else steps/2*TREAD+float(p.stair_landing)
	var stair_right := w/2-WALL-.15; var stair_left := stair_right-(float(p.stair_width)*2+.20 if folded else float(p.stair_width))
	# Leave voxel clearance as well as capsule clearance at both turning platforms.
	var z1 := d/2-maxf(1.8,p.stair_landing+WALL); var z0 := z1-run; var split_z := z0-maxf(1.5,p.stair_landing+WALL/2)
	if stair_left-.35-(-w/2+WALL)<float(p.corridor_width): return fail("楼梯旁净宽不足，请增加宽度或减小楼梯 / 通道宽度")
	var front_count := maxi(1,count-1)
	if levels>1 and (split_z-(-d/2+WALL))/front_count<2.6: return fail("前屋与楼梯平台空间不足，请增加进深、减少房间或降低层高")
	if levels==1: split_z = d/2-maxf(4.2,d*.38); stair_left=w/2-WALL
	var palette := {"wall":[.82,.76,.62],"trim":[.22,.12,.065],"floor":[.49,.34,.21],"roof":[.43,.17,.105],"glass":[.29,.39,.38],"stone":[.44,.43,.37],"shutter":[.29,.36,.23]}
	if p.style=="plaster": palette.wall=[.86,.79,.65]; palette.trim=[.27,.19,.12]
	palette.stone=[.64,.59,.47]
	var tint := float(int(p.seed)%7-3)*.012
	for channel in 3: palette.wall[channel] = clampf(palette.wall[channel]+tint,0,1)
	var plan := {"ok":true,"version":4,"parameters":p,"records":[],"rooms":[],"openings":[],"stairs":[],"routes":[],"volumes":[],"courtyards":[],"connections":[],"frame_joints":[],"entrance":[-w/2+1.2,0,-d/2-1],"size":[w,levels*h+w/2,d]}
	var annexes := annex_specs(p)
	for f in levels:
		var y := f*h; var front: float = -d/2-(float(p.jetty) if f>0 else 0.0)
		var prefix := "f%d/"%f; var start: float = split_z if p.layout=="hall" and f==1 else front
		if f==0: slab(plan,prefix+"floor",-w/2,w/2,start,d/2,y,palette.floor,f)
		else:
			slab(plan,prefix+"floor/left",-w/2,stair_left-.09,start,d/2,y,palette.floor,f)
			slab(plan,prefix+"floor/right",stair_right+.09,w/2,start,d/2,y,palette.floor,f)
			slab(plan,prefix+"floor/front",stair_left-.09,stair_right+.09,start,z0,y,palette.floor,f)
			slab(plan,prefix+"floor/back",stair_left-.09,stair_right+.09,z1,d/2,y,palette.floor,f)
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
		right_windows.append(opening("landing_window",d/2-1.05,"window",rear_id))
		# Light the lower landing, not the sloping flight/handrail behind it.
		if levels>1: right_windows.append(opening("stair_window",z0-.7,"window",rear_id))
		var front_id := ("f0/room0" if is_loft else prefix+"room0")
		front_windows.append(opening("front_window",w/2-1.2,"window",front_id))
		front_windows.append(opening("entrance" if f==0 else "upper_window",-w/2+1.2,"door" if f==0 else "window",front_id))
		if f>0 and w>=7.8:
			front_windows[0].u=w*.28; front_windows[1].u=-w*.28
			front_windows.append(opening("center_window",0,"window",front_id))
		# A street shop has a broad, divided display window; its actual opening
		# still belongs to the room and cuts both faces of the shared wall.
		if f==0 and p.template=="shop":
			front_windows[0].u=w/2-2.1
			front_windows[0].type="shopfront"
			front_windows[0].width=minf(3.2,w-4.0)
			front_windows[0].bottom=.8; front_windows[0].height=1.5
		back_windows.append(opening("rear_window",-w/2+1.2,"window",rear_id))
		if f==0 and p.compound=="rear_workshop": back_windows=[opening("yard_door",0,"door",rear_id)]
		if f<p.annex_floors:
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
		if f==0 and p.get("front_canopy",false):
			var o: Dictionary=front_windows[0] if p.template=="shop" else front_windows[1]
			var width: float=o.width+.55; var canopy_y: float=o.bottom+o.height+.28
			box(plan,"porch/canopy",Vector3(o.u,canopy_y,-d/2-.48),Vector3(width,.1,1.0),palette.roof,0,"canopy",Vector3(-12,0,0))
			box(plan,"porch/fascia",Vector3(o.u,canopy_y-.165,-d/2-.97),Vector3(width,.13,.1),palette.trim,0,"beam")
			for side in [-1,1]:
				var x: float=o.u+side*(width/2-.1)
				box(plan,"porch/wallpost"+str(side),Vector3(x,canopy_y-.38,-d/2-.035),Vector3(.14,.86,.14),palette.trim,0,"bracket")
				strut(plan,"porch/support"+str(side),Vector3(x,canopy_y-.65,-d/2-.03),Vector3(x,canopy_y-.125,-d/2-.83),.1,.12,"z",palette.trim,0,"bracket")
		if f<levels-1: staircase(plan,prefix,stair_left,stair_right,z0,z1,y,h,steps,palette,f)
		elif f>0:
			preload("res://scripts/world3d/house_stairs.gd").well_guard(plan,prefix+"well",stair_left,stair_right,z0,z1,y,palette,f)
		if f==1 and p.jetty>0:
			for i in 3:
				var x: float=[-w/2+.3,0,w/2-.3][i]
				# Corbels start in the supporting facade and end in the floor rim.
				strut(plan,prefix+"jetty_bracket%d"%i,Vector3(x,y-.65,-d/2+.035),Vector3(x,y-.11,front+.08),.18,.2,"z",palette.trim,f,"bracket")
	var extra_front: float = p.jetty if levels>1 else 0.0
	slab(plan,"roof/ceiling",-w/2,w/2,-d/2-extra_front,d/2,levels*h,palette.wall,levels)
	attic_collar(plan,"roof",-w/2,w/2,-d/2-extra_front,d/2,levels*h,palette,levels)
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
	finish_timber_frames(plan,p)
	for record in plan.records:
		record.building.floor_y = int(record.building.floor)*h
		# Keep the finished ground-floor surface above supporting terrain, avoiding z-fighting.
	return plan

static func opening(id: String, u: float, type: String, room_id: String) -> Dictionary:
	return {"id":id,"u":u,"bottom":0.0 if type=="door" else 1.0,"width":1.4 if type=="door" else 1.05,"height":2.2 if type=="door" else 1.15,"type":type,"room":room_id}

static func room(plan: Dictionary, id: String, title: String, f: int, bounds: Array, y: float) -> void:
	plan.rooms.append({"id":id,"name":title,"floor":f,"bounds":bounds,"center":[(bounds[0]+bounds[2])/2,y,(bounds[1]+bounds[3])/2]})

static func framed_wall(plan: Dictionary, key: String, axis: String, fixed: float, start: float, end: float, y: float, height: float, openings: Array, colors: Dictionary, f: int, p: Dictionary) -> void:
	wall(plan,key,axis,fixed,start,end,y,height,openings,colors,f)
	var dressing_first:int=plan.records.size()
	# End walls stop between side walls, but their exterior dressings wrap the
	# complete corner so the two facade systems actually meet.
	if axis=="x": start-=WALL; end+=WALL
	var outward := -1.0 if key.ends_with("west") or key.ends_with("north") else 1.0
	var skin := fixed+outward*(WALL/2+.045)
	var thickness: float=p.timber_width
	var timber: bool=p.style=="timber" and (f>0 or p.layout=="hall")
	# Only the outer skin carries facade details. Interior plaster remains a
	# continuous finish; both sides still use the same wall and openings.
	if timber:
		wall_box(plan,key+"/beam",axis,skin,(start+end)/2,y+height-thickness/2,end-start,thickness,.14,colors.trim,f,"beam")
		if not plan.has("timber_walls"):plan.timber_walls=[]
		plan.timber_walls.append({"key":key,"axis":axis,"skin":skin,"start":start,"end":end,"y":y,"height":height,"openings":openings.duplicate(true),"colors":colors,"floor":f,"outward":outward})
	else:
		# Staggered corner stones and a modest string course leave broad plaster
		# panels, matching the masonry houses in the supplied street reference.
		for edge in [0,1]:
			for course in floori(height/.42):
				var width:=.48 if (course+edge)%2==0 else .31
				var u: float=start+width/2 if edge==0 else end-width/2
				var bottom:=y+course*.42
				if openings.any(func(o): return Rect2(u-width/2,bottom,width,.4).intersects(Rect2(o.u-o.width/2,y+o.bottom,o.width,o.height))): continue
				wall_box(plan,key+"/quoin%d_%d"%[edge,course],axis,skin,u,bottom+.2,width,.4,.13,colors.stone,f,"stone_trim")
		wall_box(plan,key+"/course",axis,skin,(start+end)/2,y+height-.1,end-start,.2,.16,colors.stone,f,"stone_trim")
	# Low masonry base is split around doors, never an invisible threshold.
	var cuts: Array=[start,end]
	for o in openings:
		if o.type=="door": cuts.append(o.u-o.width/2-.04); cuts.append(o.u+o.width/2+.04)
	cuts.sort()
	for i in cuts.size()-1:
		var center: float=(cuts[i]+cuts[i+1])/2
		if openings.any(func(o): return o.type=="door" and absf(center-o.u)<o.width/2+.04): continue
		wall_box(plan,key+"/base%d"%i,axis,skin,center,y+.18,cuts[i+1]-cuts[i],.36,.16,colors.trim if timber else colors.stone,f,"beam" if timber else "stone_trim")
	for o in openings:
		var prefix: String=key+"/"+o.id
		# Stone surrounds sit outside the cut; narrow wood joinery remains inset.
		if not timber:
			wall_box(plan,prefix+"/stone_head",axis,skin,o.u,y+o.bottom+o.height+.09,o.width+.34,.18,.17,colors.stone,f,"stone_trim")
			if o.type=="window": wall_box(plan,prefix+"/stone_sill",axis,skin,o.u,y+o.bottom-.07,o.width+.38,.14,.25,colors.stone,f,"stone_trim")
		if o.type!="window": continue
	if p.shutters:
		for o in openings:
			if o.type!="window": continue
			# Full half-width leaves close the real opening, then rotate on outer hinges.
			for side in [-1,1]:
				var leaf: String=key+"/shutter_"+o.id+str(side)
				hinges(plan,leaf,axis,skin+outward*.08,o.u+side*o.width/2,y+o.bottom+o.height/2,o.height,side,f,false)
				var first:int=plan.records.size()
				var u: float=o.u+side*o.width/4; var width: float=o.width/2-.02
				wall_box(plan,leaf,axis,skin+outward*.08,u,y+o.bottom+o.height/2,width,o.height,.075,colors.shutter,f,"shutter")
				for level in [.22,.78]: wall_box(plan,leaf+"/rail"+str(level),axis,skin+outward*.125,u,y+o.bottom+o.height*level,width-.04,.07,.035,colors.trim,f,"frame")
				hinges(plan,leaf,axis,skin+outward*.08,o.u+side*o.width/2,y+o.bottom+o.height/2,o.height,side,f,true)
				Fixtures.attach(plan,first,leaf,"shutter",wall_position(axis,skin+outward*.08,o.u+side*o.width/2,y+o.bottom+o.height/2),hinge_sign(key,axis,side)*170,1)

	clip_shared_dressings(plan,dressing_first,key,p)

static func wall_point(axis: String, fixed: float, at: Vector2) -> Vector3:
	return Vector3(at.x,at.y,fixed) if axis=="x" else Vector3(fixed,at.y,at.x)

static func finish_timber_frames(plan:Dictionary,p:Dictionary)->void:
	# All storeys of a facade share one post layout. Windows on any storey
	# reserve clearance before intermediate bays are placed.
	var groups:Dictionary={};var thickness:float=p.timber_width
	for row:Dictionary in plan.get("timber_walls",[]):
		var tokens:Array=[]
		for token:String in row.key.split("/"):
			if token.begins_with("f") and token.substr(1).is_valid_int():continue
			tokens.append(token)
		var key:String="/".join(tokens)
		if not groups.has(key):groups[key]=[]
		groups[key].append(row)
	for rows:Array in groups.values():
		var candidates:Array=[];var openings:Array=[]
		for row:Dictionary in rows:
			candidates.append(row.start+thickness/2);candidates.append(row.end-thickness/2)
			openings.append_array(row.openings)
		for o:Dictionary in openings:
			for side in [-1,1]:candidates.append(o.u+side*(o.width/2+thickness/2+.08))
		candidates.sort();var anchors:Array=candidates.duplicate()
		for i in anchors.size()-1:
			var bays:=ceili((float(anchors[i+1])-float(anchors[i]))/float(p.bay_width))
			for j in range(1,bays):candidates.append(lerpf(anchors[i],anchors[i+1],float(j)/bays))
		candidates.sort();var posts:Array=[]
		for u:float in candidates:
			if openings.any(func(o):return absf(u-o.u)<o.width/2+thickness/2+.035):continue
			if not posts.is_empty() and u-float(posts.back())<thickness*1.5:continue
			posts.append(u)
		for row:Dictionary in rows:
			var first:int=plan.records.size();var placed:Array=[]
			for u:float in posts:
				if u<row.start+thickness/2-.001 or u>row.end-thickness/2+.001:continue
				placed.append(u)
				wall_box(plan,row.key+"/post%d"%(placed.size()-1),row.axis,row.skin-row.outward*.008,u,row.y+row.height/2,thickness,row.height,.14,row.colors.trim,row.floor,"post")
			for i in placed.size()-1:
				var a:=Vector2(placed[i],row.y+thickness/2);var b:=Vector2(placed[i+1],row.y+row.height-thickness/2)
				if i%2==1:a.x=placed[i+1];b.x=placed[i]
				if absf(a.x-b.x)<.65:continue
				if row.openings.any(func(o):return diagonal_hits(a,b,Rect2(o.u-o.width/2,row.y+o.bottom,o.width,o.height).grow(thickness))):continue
				var av:=wall_point(row.axis,row.skin-row.outward*.018,a);var bv:=wall_point(row.axis,row.skin-row.outward*.018,b)
				var part:String=row.key+"/brace%d"%i
				strut(plan,part,av,bv,thickness*.72,.14,row.axis,row.colors.trim,row.floor,"brace")
				plan.frame_joints.append({"part":part,"start":arr(av),"end":arr(bv),"supports":[row.key+"/post%d"%(i+1 if i%2==1 else i),row.key+"/post%d"%(i if i%2==1 else i+1)]})
			clip_shared_dressings(plan,first,row.key,p)
	plan.erase("timber_walls")

static func attic_collar(plan: Dictionary,key: String,x0: float,x1: float,z0: float,z1: float,y: float,colors: Dictionary,f: int,join: String="none") -> void:
	if plan.parameters.roof_solver!="unified":return
	for side in ["west","east","north","south"]:
		if (side=="east" and join=="west") or (side=="north" and join=="south"):continue
		var axis: String="z" if side in ["west","east"] else "x"
		var at:float={"west":x0+WALL/2,"east":x1-WALL/2,"north":z0+WALL/2,"south":z1-WALL/2}[side]
		wall_box(plan,key+"/collar/"+side,axis,at,(z0+z1)/2 if axis=="z" else (x0+x1)/2,y+.16,z1-z0 if axis=="z" else x1-x0-WALL*2,.32,WALL,colors.wall,f,"wall")

static func clip_shared_dressings(plan: Dictionary,first: int,key: String,p: Dictionary) -> void:
	var masks:Array=[]
	var own:String=key.get_slice("/",0)
	if own.begins_with("f"):
		for a in annex_specs(p):
			if a.join!="none":masks.append({"rect":Rect2(a.center[0]-a.width/2-.12,a.center[1]-a.depth/2-.12,a.width+.24,a.depth+.24),"top":a.roof_top})
	else:
		masks.append({"rect":Rect2(-p.width/2-.16,-p.depth/2-.16,p.width+.32,p.depth+.32),"top":p.floors*p.floor_height+.32})
	if masks.is_empty():return
	var result:Array=plan.records.slice(0,first)
	for i in range(first,plan.records.size()):
		var r:Dictionary=plan.records[i]
		var pieces:Array=[r]
		for mask in masks:
			var next:Array=[]
			for piece in pieces:
				var at:=vec(piece.position);var size:=vec(piece.size)
				if at.y-size.y/2>=mask.top:next.append(piece);continue
				if not vec(piece.rotation).is_zero_approx() or piece.has("fixture"):
					if not mask.rect.has_point(Vector2(at.x,at.z)):next.append(piece)
					continue
				var bounds:=AABB(at-size/2,size)
				var cutter:=AABB(Vector3(mask.rect.position.x,-2,mask.rect.position.y),Vector3(mask.rect.size.x,mask.top+2,mask.rect.size.y))
				if not bounds.intersects(cutter):next.append(piece);continue
				# Clip long courses as well as end quoins; retaining a crossing beam
				# merely because its centre was outside left stone visible indoors.
				var remaining:=bounds
				var fragments:Array=[]
				for axis in 3:
					if remaining.position[axis]<cutter.position[axis]:
						var low:=remaining;low.size[axis]=cutter.position[axis]-remaining.position[axis];fragments.append(low)
						remaining.size[axis]-=low.size[axis];remaining.position[axis]=cutter.position[axis]
					if remaining.end[axis]>cutter.end[axis]:
						var high:=remaining;high.position[axis]=cutter.end[axis];high.size[axis]=remaining.end[axis]-cutter.end[axis];fragments.append(high)
						remaining.size[axis]=cutter.end[axis]-remaining.position[axis]
				for k in fragments.size():
					var fragment:AABB=fragments[k]
					if fragment.size.x<.006 or fragment.size.y<.006 or fragment.size.z<.006:continue
					var copy:Dictionary=piece.duplicate(true);copy.position=arr(fragment.get_center());copy.size=arr(fragment.size)
					copy.building.part+="/clip%d"%k;copy.uuid+="_clip%d"%k;copy.editor_name=copy.building.part;next.append(copy)
			pieces=next
		result.append_array(pieces)
	plan.records=result
	var keys:Dictionary={}
	for r in result:keys[r.building.part]=true
	plan.frame_joints=plan.frame_joints.filter(func(j):return keys.has(j.part) and j.supports.all(func(k):return keys.has(k)))

static func strut(plan: Dictionary, key: String, a: Vector3, b: Vector3, thickness: float, depth: float, axis: String, color: Array, f: int, role: String) -> void:
	var delta:=b-a
	var angle:=rad_to_deg(atan2(delta.y,delta.x if axis=="x" else delta.z))
	box(plan,key,(a+b)/2,Vector3(delta.length(),thickness,depth) if axis=="x" else Vector3(depth,thickness,delta.length()),color,f,role,Vector3(0,0,angle) if axis=="x" else Vector3(-angle,0,0))

static func diagonal_hits(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	var low:=0.0; var high:=1.0; var delta:=b-a
	for axis in 2:
		if absf(delta[axis])<.00001:
			if a[axis]<rect.position[axis] or a[axis]>rect.end[axis]: return false
		else:
			var first: float=(rect.position[axis]-a[axis])/delta[axis]
			var last: float=(rect.end[axis]-a[axis])/delta[axis]
			low=maxf(low,minf(first,last)); high=minf(high,maxf(first,last))
	return low<=high

static func staircase(plan: Dictionary, key: String, left: float, right: float, z0: float, z1: float, y: float, h: float, steps: int, colors: Dictionary, f: int) -> void:
	preload("res://scripts/world3d/house_stairs.gd").build(plan,key,left,right,z0,z1,y,h,steps,colors,f)

static func roof(plan: Dictionary, key: String, at: Vector3, w: float, d: float, p: Dictionary, colors: Dictionary, f: int, skip_end := 0) -> void:
	if p.get("roof_solver","legacy")=="unified":
		unified_roof(plan,key,at,w,d,p,colors,f,skip_end)
		return
	legacy_roof(plan,key,at,w,d,p,colors,f,skip_end)

static func unified_roof(plan: Dictionary, key: String, at: Vector3, w: float, d: float, p: Dictionary, colors: Dictionary, f: int, skip_end: int) -> void:
	var crosswise: bool=p.roof_axis=="width"; var span:=d if crosswise else w; var length:=w if crosswise else d
	var pitch:=deg_to_rad(p.roof_pitch); var e: float=p.eaves
	var module:={"id":key,"rect":[at.x-w/2,at.z-d/2,at.x+w/2,at.z+d/2],"eave_y":at.y+.32,"pitch":p.roof_pitch,"axis":p.roof_axis,"style":p.roof,"floor":f,"colors":colors,"open_sides":[]}
	module.domain=[module.rect[0]-(0 if p.left_wall=="party" else e),module.rect[1]-e,module.rect[2]+(0 if p.right_wall=="party" else e),module.rect[3]+e]
	if skip_end!=0:
		var side: int=(0 if skip_end<0 else 2) if not crosswise else (3 if skip_end<0 else 1)
		var bound: int={0:1,1:2,2:3,3:0}[side]
		module.domain[bound]=module.rect[bound]; module.open_sides.append(side)
	if p.has("_roof_join"):
		var side: int=1 if p._roof_join=="west" else 0
		if side not in module.open_sides: module.open_sides.append(side)
		module.domain[2 if side==1 else 1]=module.rect[2 if side==1 else 1]
		if p.get("_roof_same_height",false):
			module.join_end=2 if side==1 else 1
			module.domain[module.join_end]=0.0
	if not plan.has("roof_modules"): plan.roof_modules=[]; plan.roof_openings=[]
	plan.roof_modules.append(module)
	var basis:=Basis(Vector3.UP,PI/2 if crosswise else 0.0)
	var cuts: Array=preload("res://scripts/world3d/medieval_dormers.gd").holes(span,length,pitch,int(p.get("dormers",0)),1 if crosswise else -1) if key=="roof" else []
	for i in cuts.size():
		var cut: Dictionary=cuts[i]; var a:=at+basis*Vector3(cut.x0,0,cut.z0); var b:=at+basis*Vector3(cut.x1,0,cut.z1)
		plan.roof_openings.append({"id":key+"/dormer%d"%i,"type":"dormer","module":key,"rect":[minf(a.x,b.x),minf(a.z,b.z),maxf(a.x,b.x),maxf(a.z,b.z)]})
	# Keep articulated joinery and the existing dormer shell. The base roof,
	# gable closures and every ridge/valley trim come only from the final solver.
	var first: int=plan.records.size()
	legacy_roof(plan,key,at,w,d,p,colors,f,skip_end)
	var kept: Array=[]
	for index in range(first,plan.records.size()):
		var record_: Dictionary=plan.records[index]; var part: String=record_.building.part
		if part.begins_with(key+"/dormer") or part.begins_with(key+"/chimney"): kept.append(record_)
	plan.records.resize(first); plan.records.append_array(kept)
	if p.chimney and key=="roof":
		var cx:=span*.22
		if not cuts.is_empty() and crosswise: cx=-cx
		var center:=at+basis*Vector3(cx,0,length*.25)
		var old_height:=(span/2-absf(cx))*tan(pitch); var roof_height:=INF
		for plane in preload("res://scripts/world3d/roof_plan.gd").planes(module): roof_height=minf(roof_height,plane.x*center.x+plane.y*center.z+plane.z-at.y)
		var shift:=roof_height-old_height
		for record_ in kept:
			if not record_.building.part.begins_with(key+"/chimney"): continue
			if record_.building.part.ends_with("stack"): record_.position[1]+=shift/2; record_.size[1]+=shift
			else: record_.position[1]+=shift
		var half:=Vector2(.36,.34) if crosswise else Vector2(.34,.36)
		plan.roof_openings.append({"id":key+"/chimney","type":"chimney","module":key,"rect":[center.x-half.x,center.z-half.y,center.x+half.x,center.z+half.y]})

static func legacy_roof(plan: Dictionary, key: String, at: Vector3, w: float, d: float, p: Dictionary, colors: Dictionary, f: int, skip_end := 0) -> void:
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
	var Dormers=preload("res://scripts/world3d/medieval_dormers.gd")
	var cuts: Array=Dormers.holes(span,length,pitch,int(p.get("dormers",0)),1 if crosswise else -1) if key=="roof" else []
	var opening_start: int=plan.openings.size()
	for side in [-1,1]:
		var over := over_left if side<0 else over_right
		var half := span/2+over; var low := -over*tan(pitch)
		if cuts.is_empty(): box(plan,key+"/slope%d"%side,Vector3(side*half/2,(rise+low)/2,(end_right-end_left)/2),Vector3(half/cos(pitch),.14,length+end_left+end_right),colors.roof,f,"roof",Vector3(0,0,-side*rad_to_deg(pitch)))
		else: Dormers.slope(plan,key,side,span,length,pitch,over,end_left,end_right,cuts,colors,f)
	for i in cuts.size(): Dormers.build(plan,key+"/dormer%d"%i,cuts[i],span,pitch,colors,f)
	box(plan,key+"/ridge",Vector3(0,rise+.08,(end_right-end_left)/2),Vector3(.26,.19,length+end_left+end_right),colors.roof,f,"roof_tiles")
	for side in [-1,1]:
		var over:=over_left if side<0 else over_right
		box(plan,key+"/fascia%d"%side,Vector3(side*(span/2+over),-over*tan(pitch)-.08,(end_right-end_left)/2),Vector3(.15,.23,length+end_left+end_right),colors.trim,f,"beam")
	for side in [-1,1]:
		if side==skip_end: continue
		box(plan,key+"/gable%d"%side,Vector3(0,rise/2,side*(length/2-WALL/2)),Vector3(span,rise,WALL),colors.wall,f,"roof")
		plan.records.back().building_shape="gable"
		var skin: float=side*(length/2+.025)
		for slope in [-1,1]: box(plan,key+"/rafter%d_%d"%[side,slope],Vector3(slope*span/4,rise/2,skin),Vector3(span/2/cos(pitch),.2,.17),colors.trim,f,"beam",Vector3(0,0,-slope*rad_to_deg(pitch)))
		if p.style=="timber":
			box(plan,key+"/tie%d"%side,Vector3(0,.1,skin),Vector3(span,.2,.17),colors.trim,f,"beam")
			box(plan,key+"/kingpost%d"%side,Vector3(0,rise/2,skin),Vector3(p.timber_width,rise,.17),colors.trim,f,"post")
			for slope in [-1,1]:
				var x: float=slope*span*.25; var top:=rise*.5
				box(plan,key+"/gablepost%d_%d"%[side,slope],Vector3(x,top/2,skin),Vector3(p.timber_width*.8,top,.17),colors.trim,f,"post")
	if p.chimney and key=="roof":
		# Roof stack only: it starts at the attic deck, not in a bedroom/stairwell.
		# Four rim stones leave a real hollow mouth above the solid lower stack.
		var cx:=span*.22; var cz:=length*.25
		if not cuts.is_empty() and crosswise: cx=-cx
		var top: float=(span/2-absf(cx))*tan(pitch)+1.25
		box(plan,key+"/chimney/stack",Vector3(cx,(top-.32)/2,cz),Vector3(.68,top-.32,.72),colors.stone,f,"stone_trim")
		for edge in [-1,1]:
			box(plan,key+"/chimney/rim_x%d"%edge,Vector3(cx+edge*.25,top-.14,cz),Vector3(.18,.36,.72),colors.stone,f,"stone_trim")
			box(plan,key+"/chimney/rim_z%d"%edge,Vector3(cx,top-.14,cz+edge*.27),Vector3(.32,.36,.18),colors.stone,f,"stone_trim")
			box(plan,key+"/chimney/cap_x%d"%edge,Vector3(cx+edge*.27,top+.08,cz),Vector3(.22,.12,.82),colors.stone,f,"stone_trim")
			box(plan,key+"/chimney/cap_z%d"%edge,Vector3(cx,top+.08,cz+edge*.3),Vector3(.32,.12,.22),colors.stone,f,"stone_trim")
	var basis := Basis(Vector3.UP,PI/2 if crosswise else 0.0)
	for index in range(first,plan.records.size()):
		var record: Dictionary = plan.records[index]
		record.position=arr(at+basis*vec(record.position)); record.rotation=arr((basis*Basis.from_euler(vec(record.rotation)*PI/180)).get_euler()*180/PI)
	for i in range(opening_start,plan.openings.size()):
		var o: Dictionary=plan.openings[i]
		if crosswise:
			o.axis="x"; o.u+=at.x; o.fixed=at.z-o.fixed
		else: o.u+=at.z; o.fixed+=at.x
		o.floor_y+=at.y

static func annex_specs(p: Dictionary) -> Array:
	var result: Array = []; var w: float = p.width; var d: float = p.depth
	if p.compound=="rear_workshop": result.append({"id":"workshop","center":[0,d/2+3+p.annex_depth/2],"width":p.annex_width,"depth":p.annex_depth,"join":"none"})
	elif p.compound=="left_wing": result.append({"id":"wing","center":[-w/2-p.annex_width/2+WALL/2,d/2-p.annex_depth/2],"width":p.annex_width,"depth":p.annex_depth,"join":"west"})
	elif p.compound=="rear_wing": result.append({"id":"wing","center":[0,d/2+p.annex_depth/2-WALL/2],"width":p.annex_width,"depth":p.annex_depth,"join":"south"})
	elif p.compound=="courtyard":
		for side in [-1,1]: result.append({"id":"wing_left" if side<0 else "wing_right","center":[side*(w-p.annex_width)/2,d/2+p.annex_depth/2-WALL/2],"width":p.annex_width,"depth":p.annex_depth,"join":"south"})
	for a in result: a.roof_top=p.annex_floors*p.floor_height+annex_rise(p)
	return result

static func annex_rise(p: Dictionary) -> float:
	var span: float=p.annex_width
	if p.roof=="hip": span=minf(span,p.annex_depth)
	return (span+p.eaves if p.roof=="shed" else span/2)*tan(deg_to_rad(p.roof_pitch))

static func build_annex(plan: Dictionary, a: Dictionary, p: Dictionary, colors: Dictionary) -> void:
	var x: float = a.center[0]; var z: float = a.center[1]; var h: float = p.floor_height
	var x0: float = x-a.width/2; var x1: float = x+a.width/2; var z0: float = z-a.depth/2; var z1: float = z+a.depth/2
	var key: String = a.id
	for f in int(p.annex_floors):
		var prefix:=key if f==0 else key+"/f%d"%f; var id:=prefix+"/room"
		room(plan,id,"作坊" if a.join=="none" else "附属房",f,[x0+WALL,z0+WALL,x1-WALL,z1-WALL],f*h)
		slab(plan,prefix+"/floor",x0,x1,z0,z1,f*h,colors.floor,f)
		for side in ["west","east","north","south"]:
			if (side=="east" and a.join=="west") or (side=="north" and a.join=="south"): continue
			var axis := "z" if side in ["west","east"] else "x"
			var fixed: float = {"west":x0+WALL/2,"east":x1-WALL/2,"north":z0+WALL/2,"south":z1-WALL/2}[side]
			var entry: bool=side=="north" and f==0
			var o := opening("entry" if entry else "window",z if axis=="z" else x,"door" if entry else "window",id)
			framed_wall(plan,prefix+"/"+side,axis,fixed,z0 if axis=="z" else x0+WALL,z1 if axis=="z" else x1-WALL,f*h,h,[o],colors,f,p)
		if a.join!="none": plan.connections.append({"from":"f%d/"%f+("room0" if p.rooms_per_floor==1 else "rear"),"to":id,"via":"f%d/"%f+("west/wing_door" if a.join=="west" else "south/"+a.id+"_door")})
	var top: float=p.annex_floors*h
	slab(plan,key+"/ceiling",x0,x1,z0,z1,top,colors.wall,p.annex_floors)
	var roof_parameters: Dictionary = p.duplicate(); roof_parameters.roof_axis="depth"; roof_parameters.left_wall="open"; roof_parameters.right_wall="open"
	# A side wing ends its eave at the shared wall; rear wings end their roof at it.
	if a.join=="west": roof_parameters.right_wall="party"
	if p.roof_solver=="unified" and a.join!="none":
		roof_parameters._roof_join=a.join; roof_parameters._roof_same_height=p.annex_floors==p.floors
		if a.join=="west" and p.annex_floors==p.floors: roof_parameters.roof_axis="width"; roof_parameters.right_wall="open"
	attic_collar(plan,key+"/roof",x0,x1,z0,z1,top,colors,p.annex_floors,a.join)
	roof(plan,key+"/roof",Vector3(x,top,z),a.width,a.depth,roof_parameters,colors,p.annex_floors,-1 if a.join=="south" else 0)
	plan.volumes.append({"rect":[x0,z0,x1,z1],"top":a.roof_top})
