extends RefCounted
## Pure helpers for the offline migration review. No importing or publishing.
const Paths=preload("res://scripts/world3d/map_paths.gd")

static func canonical(path:String)->String:
	return path.replace("\\","/").simplify_path().trim_suffix("/")

static func output_allowed(path:String,external_root:String,project_root:String)->bool:
	if not path.is_absolute_path():return false
	var target:=canonical(path);var project:=canonical(project_root).to_lower()
	if target.to_lower()==project or target.to_lower().begins_with(project+"/"):return false
	return Paths.allowed(target,canonical(external_root).path_join("review_artifacts"))

static func same(a:Variant,b:Variant)->bool:
	# JSON stores numbers as floats; camera integers must remain exact, not fail
	# because of their transport type or accept an epsilon change in a camera.
	if (a is int or a is float) and (b is int or b is float):return is_finite(float(a)) and is_finite(float(b)) and a==b
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key:Variant in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i:int in a.size():
			if not same(a[i],b[i]):return false
		return true
	return typeof(a)==typeof(b) and a==b

static func vector3(value:Variant)->bool:
	if not value is Array or value.size()!=3:return false
	for n:Variant in value:
		if not (n is int or n is float) or not is_finite(float(n)):return false
	return true

static func camera_valid(packet:Dictionary,recipe:Dictionary,source_sha:String)->bool:
	if packet.get("version")!=1 or packet.get("source_sha256")!=source_sha or not same(packet.get("recipe"),recipe):return false
	var views:Variant=packet.get("views")
	var has_receiver:bool=recipe.get("shadow_receiver",false)
	if not views is Array or views.size()!=(5 if has_receiver else 4):return false
	var receiver:Variant=packet.get("receiver",{})
	if not receiver is Dictionary:return false
	if has_receiver:
		if receiver.size()!=2 or not vector3(receiver.get("position")):return false
		var size_:Variant=receiver.get("size")
		if not size_ is Array or size_.size()!=2:return false
		for n:Variant in size_:
			if not (n is int or n is float) or not is_finite(float(n)) or n<=0:return false
	elif not receiver.is_empty():return false
	for i:int in views.size():
		var view:Variant=views[i]
		if not view is Dictionary or view.size()!=5 or not vector3(view.get("eye")) or not vector3(view.get("aim")):return false
		if same(view.eye,view.aim) or view.get("projection")!="perspective":return false
		var fov:Variant=view.get("fov")
		if not (fov is int or fov is float) or not is_finite(float(fov)) or fov<=0 or fov>=179:return false
		if i<3 and view.get("name")!=["near","medium","far"][i]:return false
		if i==3 and view.get("name") not in ["detail","leaf_detail","flag_detail"]:return false
		if i==4 and view.get("name")!="shadow_overview":return false
	return true

static func differences(a:Variant,b:Variant,path:String="",result:Array=[])->Array:
	if same(a,b):return result
	if a is Dictionary and b is Dictionary:
		for key:Variant in a:
			if not b.has(key):result.append({"path":path+"/"+str(key),"change":"missing"})
			else:differences(a[key],b[key],path+"/"+str(key),result)
		for key:Variant in b:
			if not a.has(key):result.append({"path":path+"/"+str(key),"change":"added"})
	elif a is Array and b is Array:
		if a.size()!=b.size():result.append({"path":path,"change":"count","before":a.size(),"after":b.size()})
		for i:int in mini(a.size(),b.size()):differences(a[i],b[i],path+"/"+str(i),result)
	else:result.append({"path":path,"change":"value","before":var_to_str(a),"after":var_to_str(b)})
	return result
