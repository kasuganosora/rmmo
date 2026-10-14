extends RefCounted
## A genuine two-storey hall aperture. The projecting column/arch asset is separate.
const G=preload("res://scripts/world3d/building_geometry.gd")
const W=preload("res://scripts/world3d/house_window_styles.gd")

static func enabled(p:Dictionary)->bool:
	return p.get("entrance_style","rectangular")=="round_arch_hall"

static func validate(p:Dictionary)->String:
	if not enabled(p):return ""
	if p.layout!="hall" or p.template!="house" or p.floors!=2 or p.style!="plaster" or p.compound!="none" or p.jetty!=0 or p.front_canopy:
		return "通高圆拱入口需要两层挑空大厅住宅、灰墙、独栋、无挑层和临街遮檐"
	var width:float=p.get("entrance_arch_width",2.28)
	var spring:float=p.get("entrance_arch_spring",3.67)
	if spring+width/2>=p.floor_height*2-.5:return "圆拱入口上方至少保留 0.5 米承重墙"
	if width+3.2>p.width:return "圆拱入口与边墙、另一侧窗之间空间不足"
	return ""

static func center(p:Dictionary)->float:
	# Keep masonry between the real aperture and the external corner; S12's
	# 3.82 m wide projecting component also remains inside a 12 m gable.
	return -float(p.width)/2+float(p.get("entrance_arch_width",2.28))/2+.98

static func front_openings(p:Dictionary,openings:Array,f:int)->Array:
	if not enabled(p):return openings
	var width:float=p.get("entrance_arch_width",2.28)
	var spring:float=p.get("entrance_arch_spring",3.67)
	var y:float=f*p.floor_height;var crown:=spring+width/2;var u:=center(p)
	var result:Array=[]
	for source:Dictionary in openings:
		if source.id in ["entrance","upper_window","center_window"]:continue
		var o:Dictionary=source.duplicate(true)
		if absf(o.u-u)<(o.width+width)/2+.25:continue
		result.append(o)
	if crown>y:
		result.append({"id":"entrance" if f==0 else "entrance_arch_upper","u":u,"bottom":0.0,"width":width,"height":minf(float(p.floor_height),crown-y),"type":"arch_passage","room":"f0/room0","arch_spring":spring,"arch_crown":crown})
	return result

static func clip_y(poly:Array,limit:float,above:bool)->Array:
	var result:Array=[]
	for i in poly.size():
		var a:Vector2=poly[i];var b:Vector2=poly[(i+1)%poly.size()]
		var ai:bool=a.y>=limit-.000001 if above else a.y<=limit+.000001
		var bi:bool=b.y>=limit-.000001 if above else b.y<=limit+.000001
		if ai:result.append(a)
		if ai!=bi:result.append(a.lerp(b,(limit-a.y)/(b.y-a.y)))
	var clean:Array=[]
	for point:Vector2 in result:
		if clean.is_empty() or point.distance_to(clean.back())>.00001:clean.append(point)
	if clean.size()>1 and clean[0].distance_to(clean.back())<.00001:clean.pop_back()
	return clean

static func infill(plan:Dictionary,key:String,axis:String,fixed:float,o:Dictionary,y:float,height:float,colors:Dictionary,f:int)->void:
	# Fill only the two circular spandrels, clipped at real storey levels.
	# Both render and collision use the same prisms; no rectangular sky gaps.
	var radius:float=o.width/2;var crown:float=o.arch_crown;var spring:float=o.arch_spring
	for i in 32:
		var a:=PI*i/32.;var b:=PI*(i+1)/32.
		var p:=Vector2(o.u+radius*cos(a),spring+radius*sin(a));var q:=Vector2(o.u+radius*cos(b),spring+radius*sin(b))
		var poly:Array=clip_y([p,q,Vector2(q.x,crown),Vector2(p.x,crown)],y,true)
		poly=clip_y(poly,y+height,false)
		if poly.size()<3:continue
		var area:=0.0
		for j in poly.size():area+=poly[j].cross(poly[(j+1)%poly.size()])
		if absf(area)<.000001:continue
		W.prism(plan,key+"/arch_infill%d"%i,axis,fixed,poly,G.WALL,colors.wall,f,"wall")
