extends RefCounted
## One mounted operation's immutable source metadata, never pixels or RIDs.
## Call on the scheduler owner only. Workers borrow immutable row values from
## private plan dictionaries. Explicit source refresh starts a new generation.
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const MAX_ENTRIES=1024
const RESERVED_BYTES=16*1024*1024 # 16 KiB/entry, capped 1024-character source/root keys.
var _rows:Dictionary={}
var _context:Array=[]
var hits:=0
var misses:=0

func reset()->void:_rows.clear();_context.clear();hits=0;misses=0

func estimate(requested:Dictionary,root:String)->Dictionary:
	if not Prep.Pixels.Policy.trusted():return Prep.estimate(requested,root)
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures or not Prep.valid_sources(requested):return {"rows":{},"estimated_bytes":0,"output_bytes":0}
	var context:Array=[root,Paint.source_generation,Paint.compressed_sidecars_enabled,Prep.Pixels.upload_preparation_enabled]
	if context!=_context:_rows.clear();_context=context
	var result:Dictionary={};var output:=0;var scratch:=0
	var keys:Array=requested.keys();keys.sort()
	for key:String in keys:
		var row:Dictionary={}
		if _rows.has(key):row=_rows[key];hits+=1
		else:
			var single:=Prep.estimate({key:requested[key]},root)
			row=single.rows.get(key,{});misses+=1
			# Long/unusual paths retain the original uncached behavior; this is a
			# cache bound, not a new package validation or authoring restriction.
			if _rows.size()<MAX_ENTRIES and key.length()<=1024 and root.length()<=1024:_rows[key]=row
		if row.is_empty() or output+int(row.output_bytes)>Prep.MAX_OUTPUT_BYTES:continue
		result[key]=row;output+=int(row.output_bytes);scratch=maxi(scratch,Prep.workspace_bytes(row))
	return {"rows":result,"estimated_bytes":output*2+scratch,"output_bytes":output}

func snapshot()->Dictionary:return {"hits":hits,"misses":misses,"entries":_rows.size(),"reserved_bytes":RESERVED_BYTES}
