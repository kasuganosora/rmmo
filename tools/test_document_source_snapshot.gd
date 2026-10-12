extends "res://tools/test_document_open_cursor.gd"
const Snapshot=preload("res://scripts/world3d/document_source_snapshot.gd")

func change_preserving_time(path: String) -> bool:
	var command := "$p='%s'; $t=[IO.File]::GetLastWriteTimeUtc($p); $b=[IO.File]::ReadAllBytes($p); $s=[Text.Encoding]::UTF8.GetString($b); $i=$s.IndexOf('obj_1'); if($i -lt 0){exit 3}; $b[$i+4]=50; [IO.File]::WriteAllBytes($p,$b); [IO.File]::SetLastWriteTimeUtc($p,$t); if([IO.File]::GetLastWriteTimeUtc($p).Ticks -ne $t.Ticks){exit 2}" % path.replace("'", "''")
	var output:Array=[]
	return OS.execute("powershell.exe",PackedStringArray(["-NoProfile","-NonInteractive","-Command",command]),output,true,false)==0

func to_final(value:RefCounted)->void:
	while value._phase!="signature" and not value.done:value.advance(1)

func run()->void:
	directory=Paths.cache_directory("source_snapshot_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var data:=fixture(1)
	var path:=write("snapshot",data)
	var source:Snapshot=Snapshot.read_file(path)
	check(source.error.is_empty() and source._retained and source._signature==source._bytes.get_string_from_utf8().sha256_text() and source._data==JSON.parse_string(source._bytes.get_string_from_utf8()),"digest and parsed JSON both match the same retained read")
	var callbacks:Array=[]
	var value:=Cursor.new();value.begin_snapshot(source,true,func(_phase,_done,_total):callbacks.append(true));to_final(value)
	var count:=callbacks.size();drain(value)
	check(value.document!=null and value.metrics.final_check=="bytes" and callbacks.size()==count,"snapshot cursor publishes without a callback after final complete byte check")
	check(value.document._disk_signature==FileAccess.get_sha256(path),"published document retains source SHA for save conflict checks")
	var sync=Doc.open_file(path)
	check(sync!=null and sync.records==value.document.records,"synchronous open remains equivalent")
	var regular:=Cursor.new();regular.begin_document(path);drain(regular)
	check(regular.document!=null and regular.metrics.final_check=="sha256","ordinary synchronous caller keeps final SHA path")
	var limited:Snapshot=Snapshot.read_file(path,0)
	value=Cursor.new();value.begin_snapshot(limited,true);drain(value)
	check(not limited._retained and limited._bytes.is_empty() and value.document!=null and value.metrics.final_check=="sha256","over retention limit frees raw bytes and falls back to complete final SHA")
	# Change only after every validator has finished, not merely before helper use.
	value=Cursor.new();value.begin_snapshot(source,true);to_final(value)
	var mtime:=FileAccess.get_modified_time(path);var length:=FileAccess.get_file_as_bytes(path).size()
	check(change_preserving_time(path) and FileAccess.get_modified_time(path)==mtime and FileAccess.get_file_as_bytes(path).size()==length,"same-length fixture rewrite preserves exact Windows UTC mtime")
	drain(value)
	check(value.document==null and "changed" in value.error,"late same-length same-mtime rewrite rejects actual cursor publication")
	value=Cursor.new();value.begin_snapshot(limited,true);drain(value)
	check(value.document==null,"over-limit SHA fallback also rejects changed file")
	var forged:=Cursor.new();forged.begin_document(path,{"data":data,"signature":source._signature,"bytes":FileAccess.get_file_as_bytes(path),"prepared":true,"verified":true,"source":source},true);drain(forged)
	check(forged.document==null and forged.metrics.final_check=="sha256","prepared keys cannot forge a byte-check capability or skip final SHA")
	path=write("snapshot",data);source=Snapshot.read_file(path)
	value=Cursor.new();value.begin_snapshot(source,true);to_final(value);DirAccess.remove_absolute(path);drain(value)
	check(value.document==null,"read failure at final cursor stage never publishes")
	var absent:Snapshot=Snapshot.read_file(path);value=Cursor.new();value.begin_snapshot(absent,true)
	check(value.done and value.document==null and not absent.error.is_empty(),"initial source read failure rejects")
	FileAccess.open(path,FileAccess.WRITE).store_string("invalid JSON")
	var invalid:Snapshot=Snapshot.read_file(path);value=Cursor.new();value.begin_snapshot(invalid,true)
	check(value.done and value.document==null,"invalid JSON cannot produce a trusted snapshot")
	path=write("snapshot",data)
	var file:=FileAccess.open(path,FileAccess.READ_WRITE);file.seek_end();file.store_string(" ".repeat(Snapshot.COMPARE_CHUNK+37));file.close()
	source=Snapshot.read_file(path);value=Cursor.new();value.begin_snapshot(source,true);drain(value)
	check(value.document!=null,"complete compare handles multiple chunks and short final chunk")
	value=Cursor.new();value.begin_snapshot(source,true);to_final(value)
	file=FileAccess.open(path,FileAccess.READ_WRITE);file.seek(file.get_length()-1);file.store_8(9);file.close();drain(value)
	check(value.document==null,"last-byte modification beyond first chunk rejects publication")
	Io._remove_tree(directory)
	print("DOCUMENT_SOURCE_SNAPSHOT_FINISHED failures=",failed)
	quit(0 if failed==0 else 1)
