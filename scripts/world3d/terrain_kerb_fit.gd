extends RefCounted
## Split all profile rails at heightfield triangle boundaries before projection.
## Sampling only the original endpoints bridges dips and buries crests.
const T=preload("res://scripts/world3d/terrain_surface.gd")
const K=preload("res://scripts/world3d/road_kerb.gd")

static func crossings(cuts:Array,a:Vector2,b:Vector2,columns:int,rows:int)->void:
	if maxf(a.x,b.x)<0 or minf(a.x,b.x)>columns or maxf(a.y,b.y)<0 or minf(a.y,b.y)>rows:return
	# In grid coordinates each cell uses the diagonal u-v = x-z.
	for axis in 3:
		var start:float=a.x if axis==0 else (a.y if axis==1 else a.x-a.y)
		var end:float=b.x if axis==0 else (b.y if axis==1 else b.x-b.y)
		if absf(end-start)<1e-10:continue
		var lo:int=maxi(ceili(minf(start,end)), -rows if axis==2 else 0)
		var hi:int=mini(floori(maxf(start,end)), rows if axis==1 else columns)
		for line in range(lo,hi+1):
			var t:float=(line-start)/(end-start)
			if t<=0. or t>=1.:continue
			var at:=a.lerp(b,t)
			if at.x>=-.0001 and at.x<=columns+.0001 and at.y>=-.0001 and at.y<=rows+.0001:cuts.append(t)

static func split(source:Array,record:Dictionary,terrains:Array)->Dictionary:
	var out:Array=[];var origin:=K.vec(record.position)
	var inverses:Array[Transform3D]=[]
	for terrain:Dictionary in terrains:inverses.append(T.transform(terrain).affine_inverse())
	for kerb:Dictionary in source:
		var cuts:Array=[0.,1.];var rails:Dictionary={}
		for rail in 6:
			var a:=K.vec(kerb.a[rail])+origin;var b:=K.vec(kerb.b[rail])+origin;a.y=0.;b.y=0.
			var pair:Array=[a,b]
			if rails.has(pair):continue
			rails[pair]=true
			for index in terrains.size():
				var terrain:Dictionary=terrains[index]
				var p:Vector3=inverses[index]*a;var q:Vector3=inverses[index]*b
				var columns:int=terrain.terrain_mesh.columns;var rows:int=terrain.terrain_mesh.rows
				var uv_a:=Vector2((p.x/terrain.size[0]+.5)*columns,(p.z/terrain.size[2]+.5)*rows)
				var uv_b:=Vector2((q.x/terrain.size[0]+.5)*columns,(q.z/terrain.size[2]+.5)*rows)
				crossings(cuts,uv_a,uv_b,columns,rows)
		cuts.sort()
		var clean:Array=[0.]
		# Retain the existing schema's minimum strip length; coincident rail/grid
		# intersections must not create zero-area strips or new end caps.
		var epsilon:float=maxf(1e-8,.000011/float(kerb.length))
		for t:float in cuts:
			if t-clean[-1]>epsilon and t<1.-epsilon:clean.append(t)
		clean.append(1.)
		for i in clean.size()-1:
			var low:float=clean[i];var high:float=clean[i+1];var part:=kerb.duplicate(true)
			for side:String in ["a","b"]:
				var t:float=low if side=="a" else high
				# Keep original endpoints bit-for-bit so adjoining strips agree.
				if t==0.:part[side]=kerb.a.duplicate(true)
				elif t==1.:part[side]=kerb.b.duplicate(true)
				else:
					for rail in 6:part[side][rail]=K.xyz(K.vec(kerb.a[rail]).lerp(K.vec(kerb.b[rail]),t))
			part.u=kerb.u+kerb.length*low;part.length=kerb.length*(high-low)
			part.cap_a=kerb.cap_a and low==0.;part.cap_b=kerb.cap_b and high==1.
			out.append(part)
			if out.size()>8192:return {"ok":false,"code":"terrain_projection_kerb_limit","error":"贴地路缘超过单块 8192 段，请缩小道路分块"}
	return {"ok":true,"kerbs":out}
