extends RefCounted
## Bounded protobuf wire codec. Descriptors are generated from Go's game.proto.
const Schema=preload("res://scripts/net/protocol/schema.gd").SCHEMA
const MAX_BYTES=1048576
const MAX_VALUES=100000

static func encode(message:String,data:Dictionary)->Dictionary:
	var out:=PackedByteArray()
	if not _encode(message,data,out,0) or out.size()>MAX_BYTES:return {"ok":false,"error":"invalid protobuf request"}
	return {"ok":true,"bytes":out}

static func _varint(value:int)->PackedByteArray:
	var out:=PackedByteArray()
	for i in 10:
		if i==9:out.append(value&1);return out
		if value>=0 and value<128:out.append(value);return out
		out.append((value&127)|128);value>>=7
	return out

static func _encode(message:String,data:Dictionary,out:PackedByteArray,depth:int)->bool:
	if depth>32 or not Schema.has(message):return false
	var fields:Dictionary=Schema[message];var names:Array=[]
	for f:Array in fields.values():names.append(f[0])
	for name in data:
		if name not in names:return false
	for number:int in fields:
		var f:Array=fields[number]
		if not data.has(f[0]):continue
		var values:Array=[data[f[0]]]
		if f[2]:
			if not data[f[0]] is Array:return false
			values=data[f[0]]
		for value:Variant in values:
			var kind:String=f[1];var wire:=0;var bytes:=PackedByteArray()
			if kind in ["uint32","uint64","int32","bool"]:
				if kind=="bool":
					if not value is bool:return false
				elif not value is int:return false
				if kind.begins_with("uint") and value<0:return false
				if kind=="uint32" and value>4294967295:return false
				if kind=="int32" and (value< -2147483648 or value>2147483647):return false
				bytes=_varint(int(value))
			elif kind=="double":
				if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)):return false
				wire=1;bytes.resize(8);bytes.encode_double(0,float(value))
			elif kind=="string":
				if not value is String:return false
				wire=2;bytes=value.to_utf8_buffer()
			else:
				if not value is Dictionary:return false
				wire=2
				if not _encode(kind,value,bytes,depth+1):return false
			if out.size()+bytes.size()+20>MAX_BYTES:return false
			out.append_array(_varint((number<<3)|wire))
			if wire==2:out.append_array(_varint(bytes.size()))
			out.append_array(bytes)
	return true

static func decode(message:String,bytes:PackedByteArray)->Dictionary:
	if bytes.size()>MAX_BYTES:return {"ok":false,"error":"protobuf frame exceeds limit"}
	var state:={"values":0,"error":""}
	var data:=_decode(message,bytes,0,state)
	return {"ok":state.error.is_empty(),"data":data,"error":state.error}

static func _read(bytes:PackedByteArray,at:int)->Dictionary:
	var value:=0
	for i in 10:
		if at>=bytes.size():return {}
		var b:int=bytes[at];at+=1
		if i==9 and b>1:return {}
		value|=(b&127)<<(i*7)
		if b<128:return {"value":value,"next":at}
	return {}

static func _decode(message:String,bytes:PackedByteArray,depth:int,state:Dictionary)->Dictionary:
	var out:Dictionary={};var at:=0
	if depth>32 or not Schema.has(message):state.error="invalid protobuf message";return {}
	var fields:Dictionary=Schema[message]
	while at<bytes.size():
		state.values+=1
		if state.values>MAX_VALUES:state.error="protobuf value budget";return {}
		var tag:=_read(bytes,at)
		if tag.is_empty() or tag.value<=0:state.error="invalid protobuf tag";return {}
		at=tag.next;var number:int=tag.value>>3;var wire:int=tag.value&7
		if number<1 or number>536870911:state.error="invalid protobuf field";return {}
		var f:Array=fields.get(number,[]);var value:Variant
		if not f.is_empty():
			var expected:=1 if f[1]=="double" else (0 if f[1] in ["uint32","uint64","int32","bool"] else 2)
			if wire!=expected:state.error="protobuf wire type mismatch";return {}
		match wire:
			0:
				var item:=_read(bytes,at)
				if item.is_empty():state.error="truncated protobuf varint";return {}
				value=item.value;at=item.next
			1,5:
				var size:=8 if wire==1 else 4
				if at+size>bytes.size():state.error="truncated protobuf scalar";return {}
				if not f.is_empty():value=bytes.decode_double(at)
				at+=size
			2:
				var length:=_read(bytes,at)
				if length.is_empty() or length.value<0 or length.value>bytes.size()-length.next:state.error="truncated protobuf payload";return {}
				at=length.next
				if not f.is_empty():
					var payload:=bytes.slice(at,at+length.value)
					value=payload.get_string_from_utf8() if f[1]=="string" else _decode(f[1],payload,depth+1,state)
				at+=length.value
			_:
				state.error="unsupported protobuf wire type";return {}
		if not state.error.is_empty():return {}
		if f.is_empty():continue
		if f[1]=="bool":value=value!=0
		elif f[1]=="int32":
			value=value&0xffffffff
			if value>2147483647:value-=4294967296
		elif f[1].begins_with("uint") and (value<0 or (f[1]=="uint32" and value>4294967295)):
			state.error="protobuf unsigned integer overflow";return {}
		elif f[1]=="double" and not is_finite(value):state.error="nonfinite protobuf coordinate";return {}
		if f[2]:
			if not out.has(f[0]):out[f[0]]=[]
			out[f[0]].append(value)
		else:out[f[0]]=value
	return out
