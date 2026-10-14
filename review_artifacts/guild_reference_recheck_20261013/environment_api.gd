extends SceneTree
func _initialize():
	for c in ClassDB.class_get_integer_constant_list('Environment'):
		if 'REFLECT' in c:print(c,'=',ClassDB.class_get_integer_constant('Environment',c))
	for p in Environment.new().get_property_list():
		if 'reflect' in p.name:print(p)
	quit()
