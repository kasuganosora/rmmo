extends RefCounted
## Bounded interpolating Hermite path shared by river and wall authoring.
static func sample(raw:Array,spacing:float=2.,closed:bool=false,tension:float=.5)->Dictionary:
	if raw.size()<2 or raw.size()>128:return {"ok":false,"error":"路径需 2～128 个控制点"}
	var points:Array[Vector2]=[]
	for p:Array in raw:points.append(Vector2(p[0],p[1]))
	var count:=points.size();var result:Array=[];var spans:Array=[];var anchors:Array=[]
	for i in count-(0 if closed else 1):
		var a:Vector2=points[i];var b:Vector2=points[(i+1)%count]
		if a.distance_to(b)<.1:return {"ok":false,"error":"相邻控制点太近"}
		var before:Vector2=points[(i-1+count)%count] if closed or i>0 else a*2-b
		var after:Vector2=points[(i+2)%count] if closed or i+2<count else b*2-a
		var m:Vector2=(b-before)*tension;var n:Vector2=(after-a)*tension
		var steps:=maxi(1,ceili((a.distance_to(b)+m.length()+n.length())/(3.*spacing)))
		anchors.append(result.size())
		for j in steps:
			var t:=float(j)/steps;var u:=t*t;var v:=u*t
			var p:Vector2=(2*v-3*u+1)*a+(v-2*u+t)*m+(-2*v+3*u)*b+(v-u)*n
			result.append([p.x,p.y]);spans.append({"segment":i,"t":t})
			if result.size()>512:return {"ok":false,"error":"曲线路径采样超过 512，请分成多段"}
	if not closed:anchors.append(result.size());result.append(raw[-1].duplicate());spans.append({"segment":count-2,"t":1.})
	if result.size()>512:return {"ok":false,"error":"曲线路径采样超过 512，请分成多段"}
	var edges:=result.size() if closed else result.size()-1
	for i in edges:
		for j in range(i+2,edges):
			if closed and i==0 and j==edges-1:continue
			var a:Array=result[i];var b:Array=result[(i+1)%result.size()];var c:Array=result[j];var d:Array=result[(j+1)%result.size()]
			if Geometry2D.segment_intersects_segment(Vector2(a[0],a[1]),Vector2(b[0],b[1]),Vector2(c[0],c[1]),Vector2(d[0],d[1]))!=null:return {"ok":false,"error":"曲线自交，请调整控制点"}
	return {"ok":true,"points":result,"spans":spans,"anchors":anchors}
