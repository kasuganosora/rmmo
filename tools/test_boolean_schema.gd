extends SceneTree
const S=preload("res://scripts/world3d/document_schema.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
const Kerb=preload("res://scripts/world3d/road_kerb.gd")
var failures:=0
var cases:=0
func _initialize()->void:run.call_deferred()
func compare(value:Variant,schema:Dictionary)->void:
	cases+=1
	if S.matches(value,schema)!=S.validate(value,schema).is_empty():
		failures+=1;print("MISMATCH ",value," ",schema)
func run()->void:
	var values:Array=[null,true,false,0,1,-1,1.5,INF,-INF,NAN,"", "a", "abcd",StringName("a"),[],{},[0,1],[0,1.5],[INF],["a"],PackedFloat64Array([1,2])]
	var schemas:Array=[{},S.number(-1,1),S.number(-2,2,true),{"type":"string","maxLength":2},{"type":"boolean"},{"enum":[null,0,"a"]},{"type":"number","enum":[0,1]},S.vector(-1,1)]
	for item:Dictionary in [S.number(-1,1),S.number(-2,2,true),{"type":"integer","enum":[0,1]},{"type":"string"}]:
		schemas.append({"type":"array","items":item,"minItems":0,"maxItems":3,"enum":[[],[0,1],["a"]]})
	for schema:Dictionary in schemas:
		for value:Variant in values:compare(value,schema)
	var nested:={"type":"object","properties":{"points":{"type":"array","items":S.vector(-1000,1000)},"label":{"type":"string"}},"required":["points"]}
	for value:Variant in [{},{"points":[]},{"points":[[1,2,3]],"label":"x"},{"points":[[1,2]]},{"points":[[1,INF,3]]},{"points":[],"extra":1}]:compare(value,nested)
	var section:Array=[]
	for i in 6:section.append([i*.1,0.0,0.0])
	var parts:Array=[]
	for i in 1024:parts.append({"a":section.duplicate(true),"b":section.duplicate(true),"u":float(i),"length":1.0,"cap_a":true,"cap_b":false})
	compare(parts,Kerb.schema())
	for replacement:Variant in [NAN,INF,-1000.01,1000.01,"0",null,true,0.0]:
		parts[1023].b[5][2]=replacement;compare(parts,Kerb.schema())
	parts[1023].b[5][2]=0.0;parts[1023].unsupported=true;compare(parts,Kerb.schema())
	var fixture:=preload("res://tools/test_road_dependency_index.gd").new()
	var record:Dictionary=fixture.road("stress",0);fixture.free();record.road_mesh.kerbs=parts;parts[1023].erase("unsupported")
	var original:=var_to_bytes(record)
	for replacement:Variant in [0.0,NAN,.151,"bad"]:
		record.road_mesh.grade[0]=replacement
		Road.boolean_schema_enabled=false;var expected:=Road.valid(record)
		Road.boolean_schema_enabled=true;cases+=1
		if Road.valid(record)!=expected:failures+=1
	print("BOOLEAN_SCHEMA cases=",cases," failures=",failures," fixture_bytes=",original.size())
	quit(0 if failures==0 else 1)
