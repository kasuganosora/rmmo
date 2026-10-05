extends RefCounted
## One resolved family per building; true curved head infill and supported sills.
const G=preload("res://scripts/world3d/building_geometry.gd")
const Prism=preload("res://scripts/world3d/roof_mesh.gd")
const IDS=["cross_lattice","diamond_lattice","round_arch","tall_shutter"]
static func choices()->Array:
	return [{"id":"casement","name":"原有双扇格窗"},{"id":"random","name":"整栋随机方案"},{"id":"cross_lattice","name":"细长十字斜撑窗"},{"id":"diamond_lattice","name":"菱格托台窗"},{"id":"round_arch","name":"圆拱分格窗"},{"id":"tall_shutter","name":"细长窗板格窗"}]
static func prepare(plan:Dictionary,o:Dictionary,height:float)->void:
	if o.type!="window" or plan.parameters.get("window_style","casement")=="casement":return
	o.window_style=plan.parameters.window_style
	if height>2:
		o.width=minf(o.width,.92 if o.window_style=="cross_lattice" else 1.05)
		o.bottom=.8;o.height=minf(1.85,height-o.bottom-.30)
	else:o.height=minf(o.height,height-o.bottom-.14)

static func prism(plan:Dictionary,key:String,axis:String,fixed:float,points:Array,depth:float,color:Array,f:int,role:String)->void:
	var polygon:Array=[]
	var offset:=G.wall_position(axis,fixed,points[0].x,points[0].y)
	for p:Vector2 in points:polygon.append(G.arr(G.wall_position(axis,-depth/2,p.x-points[0].x,p.y-points[0].y)))
	var extrusion:=Vector3(0,0,depth) if axis=="x" else Vector3(depth,0,0)
	var r:=Prism.record(key,polygon,extrusion,color,f,0,"gable");r.building.role=role
	r.position=G.arr(G.vec(r.position)+offset);r.roof_mesh.uv_origin=r.position.duplicate()
	if role in ["frame","stone_trim","bracket"]:r.collision="none"
	plan.records.append(r)

static func bar(plan:Dictionary,key:String,axis:String,fixed:float,a:Vector2,b:Vector2,width:float,color:Array,f:int)->void:
	var first:=G.wall_position(axis,fixed,a.x,a.y);var last:=G.wall_position(axis,fixed,b.x,b.y)
	var rotation:=Basis(Quaternion(Vector3.UP,(last-first).normalized())).get_euler()*180/PI
	G.box(plan,key,(first+last)/2,Vector3(width,first.distance_to(last)+.01,width),color,f,"frame",rotation)
	plan.records.back().collision="none"

static func arch_band(plan:Dictionary,key:String,axis:String,fixed:float,u:float,spring:float,inner:float,outer:float,depth:float,color:Array,f:int,role:String)->void:
	for i in 16:
		var a:=PI*i/16.;var b:=PI*(i+1)/16.
		prism(plan,key+str(i),axis,fixed,[Vector2(u+inner*cos(a),spring+inner*sin(a)),Vector2(u+outer*cos(a),spring+outer*sin(a)),Vector2(u+outer*cos(b),spring+outer*sin(b)),Vector2(u+inner*cos(b),spring+inner*sin(b))],depth,color,f,role)

static func build(plan:Dictionary,key:String,axis:String,fixed:float,o:Dictionary,y:float,colors:Dictionary,f:int)->void:
	var style:String=plan.parameters.window_style;var prefix:String=key+"/"+str(o.id)
	var bottom:float=y+o.bottom;var top:float=bottom+o.height;var left:float=o.u-o.width/2;var right:float=o.u+o.width/2
	var outward:float=-1 if key.ends_with("north") or key.ends_with("west") else 1
	var radius:float=o.width/2;var spring:float=top-radius;var arched:=style=="round_arch"
	var rectangular_top:float=spring if arched else top
	# Close the rectangular wall cut above the circular opening with real wall
	# wedges, so neither visuals nor collision leave square corner holes.
	if arched:
		for i in 16:
			var a:=PI*i/16.;var b:=PI*(i+1)/16.
			var p:=Vector2(o.u+radius*cos(a),spring+radius*sin(a));var q:=Vector2(o.u+radius*cos(b),spring+radius*sin(b))
			var poly:Array=[p,q]
			if absf(q.y-top)>.0001:poly.append(Vector2(q.x,top))
			if absf(p.y-top)>.0001:poly.append(Vector2(p.x,top))
			prism(plan,prefix+"/arch_wall"+str(i),axis,fixed,poly,G.WALL,colors.wall,f,"wall")
		arch_band(plan,prefix+"/arch_frame",axis,fixed,o.u,spring,radius-.055,radius+.035,G.WALL+.075,colors.trim,f,"frame")
		arch_band(plan,prefix+"/arch_stone",axis,fixed+outward*.15,o.u,spring,radius+.045,radius+.19,.14,colors.get("stone",colors.wall),f,"stone_trim")
		var fan:Array=[Vector2(o.u-radius+.065,spring+.015),Vector2(o.u+radius-.065,spring+.015)]
		for i in range(1,16):fan.append(Vector2(o.u+(radius-.065)*cos(PI*i/16.),spring+(radius-.065)*sin(PI*i/16.)))
		prism(plan,prefix+"/fanlight",axis,fixed,fan,.025,colors.glass,f,"window")
		bar(plan,prefix+"/fan_mullion",axis,fixed,Vector2(o.u,spring),Vector2(o.u,top-.06),.045,colors.trim,f)
	else:
		G.wall_box(plan,prefix+"/head",axis,fixed,o.u,top,o.width+.14,.10,G.WALL+.075,colors.trim,f,"frame")
		G.wall_box(plan,prefix+"/stone_head",axis,fixed+outward*.15,o.u,top+.08,o.width+.36,.17,.16,colors.get("stone",colors.wall),f,"stone_trim")
	for side in [-1,1]:G.wall_box(plan,prefix+"/jamb"+str(side),axis,fixed,o.u+side*(radius-.015),(bottom+rectangular_top)/2,.095,rectangular_top-bottom+.1,G.WALL+.075,colors.trim,f,"frame")
	for side in [-1,1]:G.wall_box(plan,prefix+"/stone_jamb"+str(side),axis,fixed+outward*.15,o.u+side*(radius+.12),(bottom+rectangular_top)/2,.15,rectangular_top-bottom,.16,colors.get("stone",colors.wall),f,"stone_trim")
	G.wall_box(plan,prefix+"/sill",axis,fixed,o.u,bottom,o.width+.18,.10,G.WALL+.14,colors.trim,f,"frame")
	if style!="diamond_lattice":G.wall_box(plan,prefix+"/stone_sill",axis,fixed+outward*.15,o.u,bottom-.10,o.width+.39,.15,.24,colors.get("stone",colors.wall),f,"stone_trim")
	# The whole rectangular casement and lattice share one hinge group.
	var leaf:String=prefix+"/casement";var center:float=(bottom+rectangular_top)/2;var h:float=rectangular_top-bottom-.13;var w:float=o.width-.13;var hinge_u:float=left+.055
	G.window_hinges(plan,leaf,axis,fixed,hinge_u,center,h,-1,f,false)
	var first:int=plan.records.size()
	G.wall_box(plan,leaf+"/glass",axis,fixed,o.u,center,w-.07,h-.07,.025,colors.glass,f,"window")
	for side in [-1,1]:
		G.wall_box(plan,leaf+"/stile"+str(side),axis,fixed,o.u+side*w/2,center,.055,h+.055,.065,colors.trim,f,"frame")
		G.wall_box(plan,leaf+"/rail"+str(side),axis,fixed,o.u,center+side*h/2,w+.055,.055,.065,colors.trim,f,"frame")
	if style in ["cross_lattice","diamond_lattice"]:
		for row in 2:
			var low:float=center-h/2+row*h/2;var high:float=low+h/2
			if style=="cross_lattice":
				bar(plan,leaf+"/cross_a"+str(row),axis,fixed,Vector2(o.u-w/2,low),Vector2(o.u+w/2,high),.045,colors.trim,f)
				bar(plan,leaf+"/cross_b"+str(row),axis,fixed,Vector2(o.u+w/2,low),Vector2(o.u-w/2,high),.045,colors.trim,f)
			else:
				var points:Array=[Vector2(o.u,low),Vector2(o.u+w/2,(low+high)/2),Vector2(o.u,high),Vector2(o.u-w/2,(low+high)/2)]
				for j in 4:bar(plan,leaf+"/diamond%d_%d"%[row,j],axis,fixed,points[j],points[(j+1)%4],.04,colors.trim,f)
	else:bar(plan,leaf+"/mullion",axis,fixed,Vector2(o.u,center-h/2),Vector2(o.u,center+h/2),.04,colors.trim,f)
	G.wall_box(plan,leaf+"/transom",axis,fixed,o.u,center,w,.05,.065,colors.trim,f,"frame")
	G.window_hinges(plan,leaf,axis,fixed,hinge_u,center,h,-1,f,true)
	G.iron(plan,leaf+"/latch",axis,fixed-outward*.045,right-.08,center,.035,.12,.025,f)
	G.Fixtures.attach(plan,first,leaf,"window",G.wall_position(axis,fixed,hinge_u,center),G.hinge_sign(key,axis,-1)*95,0)
	if style=="diamond_lattice":
		var shelf:float=fixed+outward*.19
		G.wall_box(plan,prefix+"/projecting_sill",axis,shelf,o.u,bottom-.09,o.width+.38,.12,.48,colors.trim,f,"frame")
		for side in [-1,1]:
			var u:float=o.u+side*o.width*.34
			var a:=G.wall_position(axis,fixed+outward*.11,u,bottom-.43);var b:=G.wall_position(axis,fixed+outward*.39,u,bottom-.13)
			G.box(plan,prefix+"/sill_bracket"+str(side),(a+b)/2,Vector3(.075,a.distance_to(b),.075),colors.trim,f,"bracket",Basis(Quaternion(Vector3.UP,(b-a).normalized())).get_euler()*180/PI)
	G.curtains(plan,prefix,axis,fixed,o,y,colors,f)
