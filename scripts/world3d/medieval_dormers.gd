extends "res://scripts/world3d/building_geometry.gd"
## Dormers replace roof patches, not fake windows pasted over an unbroken roof.

static func holes(span: float, length: float, pitch: float, count: int, side: int) -> Array:
	var result: Array=[]
	var front:=span/2-.5
	var back:=maxf(.25,front-minf(1.5,1.0/tan(pitch)))
	for i in count:
		var z:=lerpf(-length/2,length/2,float(i+1)/(count+1))
		result.append({"x0":minf(side*back,side*front),"x1":maxf(side*back,side*front),"z0":z-.75,"z1":z+.75,"front":side*front,"back":side*back,"z":z,"side":side})
	return result

static func slope(plan: Dictionary, key: String, side: int, span: float, length: float, pitch: float, over: float, end_left: float, end_right: float, cuts: Array, colors: Dictionary, f: int) -> void:
	var xs: Array=[-span/2-over if side<0 else 0.0,0.0 if side<0 else span/2+over]
	var zs: Array=[-length/2-end_left,length/2+end_right]
	for cut in cuts:
		if cut.side!=side: continue
		xs.append(cut.x0); xs.append(cut.x1); zs.append(cut.z0); zs.append(cut.z1)
	xs.sort(); zs.sort()
	for i in xs.size()-1:
		for j in zs.size()-1:
			if float(xs[i+1])-float(xs[i])<.001 or float(zs[j+1])-float(zs[j])<.001: continue
			var x: float=(xs[i]+xs[i+1])/2; var z: float=(zs[j]+zs[j+1])/2
			if cuts.any(func(c):return x>c.x0 and x<c.x1 and z>c.z0 and z<c.z1): continue
			box(plan,key+"/slope%d/patch%d_%d"%[side,i,j],Vector3(x,(span/2-absf(x))*tan(pitch),z),Vector3((xs[i+1]-xs[i])/cos(pitch),.14,zs[j+1]-zs[j]),colors.roof,f,"roof",Vector3(0,0,-side*rad_to_deg(pitch)))

static func build(plan: Dictionary, key: String, cut: Dictionary, span: float, pitch: float, colors: Dictionary, f: int) -> void:
	var base: float=(span/2-absf(cut.front))*tan(pitch)-.04
	var head:=base+1.4
	var depth: float=absf(cut.front-cut.back)
	var x: float=(cut.front+cut.back)/2
	var width:=1.5
	var opening: Array=[{"id":"window","u":cut.z,"bottom":.18,"width":.98,"height":1.05,"type":"window","room":"attic"}]
	wall(plan,key+("/west" if cut.side<0 else "/east"),"z",cut.front,cut.z0,cut.z1,base,1.4,opening,colors,f)
	# Cheeks follow the main roof slope; lower edges are buried in its thickness.
	for edge in [-1,1]:
		for i in 8:
			var a: float=lerpf(cut.back,cut.front,float(i)/8)
			var b: float=lerpf(cut.back,cut.front,float(i+1)/8)
			var low: float=(span/2-maxf(absf(a),absf(b)))*tan(pitch)-.09
			box(plan,key+"/cheek%d_%d"%[edge,i],Vector3((a+b)/2,(low+head)/2,cut.z+edge*(width/2-.05)),Vector3(depth/8+.002,head-low,.1),colors.wall,f,"wall")
	box(plan,key+"/gable",Vector3(cut.front,head+.25,cut.z),Vector3(width,.5,.16),colors.wall,f,"wall",Vector3(0,90,0))
	plan.records.back().building_shape="gable"
	# Close the short rear cheek above the main slope as well. The cavity below
	# the slope remains connected to the attic, without an outdoor gap at the cap.
	var rear_base: float=(span/2-absf(cut.back))*tan(pitch)-.07
	box(plan,key+"/back",Vector3(cut.back,(rear_base+head)/2,cut.z),Vector3(.12,head-rear_base,width),colors.wall,f,"wall")
	box(plan,key+"/back_gable",Vector3(cut.back,head+.25,cut.z),Vector3(width,.5,.12),colors.wall,f,"wall",Vector3(0,90,0))
	plan.records.back().building_shape="gable"
	var half:=width/2+.15; var angle:=atan2(.5,width/2)
	for edge in [-1,1]:
		box(plan,key+"/slope"+str(edge),Vector3(x+cut.side*.1,head+.25-.05,cut.z+edge*half/2),Vector3(depth+.25,.12,half/cos(angle)),colors.roof,f,"roof",Vector3(edge*rad_to_deg(angle),0,0))
		box(plan,key+"/fascia"+str(edge),Vector3(cut.front+cut.side*.16,head+.25-.05,cut.z+edge*half/2),Vector3(.12,.13,half/cos(angle)),colors.trim,f,"beam",Vector3(edge*rad_to_deg(angle),0,0))
	box(plan,key+"/ridge",Vector3(x+cut.side*.1,head+.57,cut.z),Vector3(depth+.3,.13,.17),colors.roof,f,"roof_tiles")
