extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Placement=preload("res://scripts/world_editor/residential_placement_tools.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 var rows:Array=[];var errors:Array=[]
 var base:="D:/code/rmmo_runtime/review_artifacts/block_planning_20261017"
 for report:String in ["http.json","boundaries.json"]:
  var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base.path_join(report)))
  var doc=Doc.open_file(source.map_path)
  if doc==null:errors.append("Cannot open "+str(source.map_path));continue
  var dependencies:Dictionary={};var issue:=Placement._dependencies(doc.records,dependencies)
  if not issue.is_empty():errors.append(issue)
  rows.append({"report":report,"map_path":source.map_path,"map_sha256":FileAccess.get_sha256(source.map_path),"record_count":doc.records.size(),"dependencies":dependencies})
 var file:=FileAccess.open(base.path_join("native_dependencies.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify({"maps":rows,"errors":errors},"\t"));file.close()
 print("NATIVE_DEPENDENCIES maps=%d errors=%d"%[rows.size(),errors.size()]);quit(0 if errors.is_empty() else 1)
