extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var path:="C:/Users/luna/AppData/Roaming/Godot/app_userdata/rmmo/world3d_navigation/c03aacc390f6c5a870d1a03597c2aec1c7f8626929dcb67e1fd91dcd8e9832ee.bin"
	var f:=FileAccess.open(path,FileAccess.READ);f.get_buffer(32);var data:Dictionary=bytes_to_var(f.get_buffer(f.get_length()-32));f.close()
	var edges:Dictionary={};var results:Array=[]
	for i in data.polygons.size():
		var p:PackedInt32Array=data.polygons[i]
		for j in p.size():
			var a:Vector3=data.vertices[p[j]];var b:Vector3=data.vertices[p[(j+1)%p.size()]]
			var key:Array=[a,b];key.sort()
			if not edges.has(key):edges[key]=[]
			edges[key].append(i)
	for key:Array in edges:
		if edges[key].size()<=2:continue
		var rows:Array=[]
		for index:int in edges[key]:
			var points:Array=[]
			for at:int in data.polygons[index]:
				var v:Vector3=data.vertices[at];points.append([v.x,v.y,v.z])
			rows.append({"index":index,"points":points})
		results.append(rows)
	f=FileAccess.open("D:/code/rmmo_runtime/review_artifacts/nonperformance_fixes_20261012/nav_edges.json",FileAccess.WRITE);f.store_string(JSON.stringify(results));f.close()
	print("CONFLICTING_EDGES ",results.size());quit()
