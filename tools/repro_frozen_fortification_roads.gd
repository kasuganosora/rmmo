extends "res://tools/test_world3d_mcp.gd"
const City=preload("res://scripts/world3d/city_layout.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
func run()->void:
 var path="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf"
 var digest=FileAccess.get_sha256(path)
 var empty=Doc.new();var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=empty;session.world3d_editor_path=""
 editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;root.add_child(editor);await settle()
 while editor._load_job!=null and editor._load_job.active:await process_frame
 editor._doc=Doc.open_file(path);editor._city.refresh();editor._authoring.refresh()
 var result=editor._roads.prepare({})
 var report={"candidate_sha256":digest,"unchanged":FileAccess.get_sha256(path)==digest,"ok":result.ok,"error":result.get("error",""),"conflicts":result.get("conflicts",[])}
 print(JSON.stringify(report))
 var suffix="after" if "--after" in OS.get_cmdline_user_args() else "before"
 var file=FileAccess.open(OUT+"/frozen_road_repro_"+suffix+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
 quit(0)
