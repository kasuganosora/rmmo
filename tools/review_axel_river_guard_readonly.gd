extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Layout=preload("res://scripts/world_editor/terrain_layout_tools.gd")
const Batch=preload("res://scripts/world3d/terrain_stroke_batch.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const MAP="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf"
const EXPECTED="c1ee7f095eac5bd937d92f7653697e961d942b674814e9e2cab66301b61e2f73"
class Source extends Node3D:
 var _doc
 func _record_editable(r:Dictionary)->bool:return not r.get("locked",false) and not r.get("hidden",false)
func _initialize():
 if FileAccess.get_sha256(MAP)!=EXPECTED:quit(1);return
 var doc=Doc.open_file(MAP)
 if doc==null:quit(1);return
 var source=Source.new();source._doc=doc
 var working=Doc.new();working.apply_recovery(doc.recovery_snapshot())
 var input=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/functional_buildings_apply_terrain_failure_first.json"))
 var touched={}
 for request:Dictionary in input.terrain_request.strokes:
  var batch=Batch.prepare(working.records,working._find(request.id),request)
  if not batch.ok:push_error(str(batch));source.free();quit(1);return
  Layout.replace_records(working,batch.entries)
  for e:Dictionary in batch.entries:touched[e.record.uuid]=true
 var changes=[]
 for id:String in touched:changes.append({"record":working._find(id)})
 var before=City.token(doc.recovery_snapshot())
 var result=Layout.river_guard(source,changes)
 var report={"candidate_sha256":EXPECTED,"guard":result,"touched_tiles":touched.keys(),"strokes":input.terrain_request.strokes,"memory_unchanged":before==City.token(doc.recovery_snapshot()),"disk_unchanged":FileAccess.get_sha256(MAP)==EXPECTED,"core_sha256":FileAccess.get_sha256("res://scripts/world_editor/terrain_layout_tools.gd"),"scope":"read-only actual candidate, two actual final-state native Batch stamps then river_guard only; no road, follow, save or GPU"}
 FileAccess.open(OUT+"/river_guard_independent_candidate_review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print(JSON.stringify(report));source.free();quit(0 if result.ok and report.memory_unchanged and report.disk_unchanged else 1)
