extends RefCounted
## A successful main-thread retirement only destroys remaining owner slots.
## Departed nodes usually vanished during streaming before logical retirement.
static func collect(ids:Array,meshes:Dictionary,bodies:Dictionary)->Dictionary:
	var owned:Array=[];var nodes:Array=[]
	for id:String in ids:
		var visual:bool=meshes.has(id)
		if visual:
			if is_instance_valid(meshes[id]):nodes.append(meshes[id])
		if visual or bodies.has(id):owned.append(id)
	return {"ids":owned,"nodes":nodes}
