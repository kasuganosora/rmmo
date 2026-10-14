extends "res://tools/review_guild_reference_camera.gd"
## Each independent final prop receives native roundtrip and the same PBR rig.
func run()->void:
	var filters:PackedStringArray=[]
	var library_out:='D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/final_library'
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with('--only='):filters=arg.trim_prefix('--only=').split(',')
		if arg.begins_with('--out='):library_out=arg.trim_prefix('--out=').replace('\\','/').simplify_path()
	if DisplayServer.get_name()=='headless':print('REFERENCE_LIBRARY_SYNTAX_OK');quit();return
	if not library_out.begins_with('D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/'):quit(2);return
	create_timer(2400).timeout.connect(func():push_error('REFERENCE_LIBRARY_TIMEOUT');quit(124))
	var manifest:=read_json('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3/repair_manifest.json')
	var summaries:Array=[];var failed:Array=[]
	review_kind='prop'
	for row:Dictionary in manifest.library:
		if not filters.is_empty() and not row.asset_id in filters:continue
		row.id=row.asset_id;source=row.path
		var doc:=GLTFDocument.new();var state:=GLTFState.new()
		if doc.append_from_file(source,state)!=OK:failed.append(row.id);continue
		var lod:=preload('res://scripts/world3d/model_lod_preparation.gd').prepare(state)
		var scene:=Io.generate_scene(doc,state);doc=null;state=null
		if scene==null:failed.append(row.id);continue
		var folder:=library_out+'/'+str(row.id)
		await review_one(scene,row,folder)
		report.lod_derivation=lod
		check(report.get('gallery_completed',false),'all property review views completed')
		check(FileAccess.get_sha256(source)==row.sha256,'actual source SHA matches manifest')
		report.passed=report.failures.is_empty();put(folder+'/report.json',report)
		summaries.append({'id':row.id,'sha256':row.sha256,'passed':report.passed,'report':folder+'/report.json'})
		if not report.passed:failed.append(row.id)
	put(library_out+'/summary.json',{'items':summaries,'failures':failed,'passed':failed.is_empty()})
	print('REFERENCE_LIBRARY_COMPLETE count=',summaries.size(),' failures=',failed);quit(0 if failed.is_empty() else 1)
