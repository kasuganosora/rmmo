extends RefCounted
## Standalone reproduction before joining the runtime retirement transaction.
static func collect(ids:Array,meshes:Dictionary,bodies:Dictionary)->Dictionary:
	var visuals:Array=[];var collisions:Array=[];var nodes:Array=[]
	for id:String in ids:
		if meshes.has(id):
			visuals.append(id)
			if is_instance_valid(meshes[id]):nodes.append(meshes[id])
		if bodies.has(id):collisions.append(id)
	return {"visuals":visuals,"bodies":collisions,"nodes":nodes}
