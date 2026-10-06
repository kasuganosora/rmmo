extends SceneTree
func _initialize()->void:
 for name:String in ["SkeletonModifier3D","Skeleton3D","IKModifier3D"]:
  if not ClassDB.class_exists(name):print(name," unavailable");continue
  print(name," available")
  for method:Dictionary in ClassDB.class_get_method_list(name,true):print(" method ",method.name," ",method.args)
  for property:Dictionary in ClassDB.class_get_property_list(name,true):print(" property ",property.name," ",property.type)
 quit()

