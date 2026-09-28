extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
const Body=preload("res://scripts/char/female_axis_body.gd")
const Motion=preload("res://scripts/char/character_axis_animation.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 var b=Body.new();root.add_child(b);b.initialize();assert(b.enable_compute())
 var m=Motion.new();assert(m.install(b.skeleton,load(Art.path("characters/animations/female_base_v2_universal.res"))))
 for clip in ["idle","cast","dash","death","idle"]:
  var length:float=m.library.get_animation(clip).length
  for frame in 31:assert(m.apply(b,clip,length*frame/30.0))
  assert(m.apply(b,clip,0.5))
  print("CLIP ",clip)
  for n in b.nodes:
   if n.name in ["lForeArm","rForeArm","lShldr","rShldr"]:print(n.name," ",n.angles*180/PI)
 b.free();quit()
