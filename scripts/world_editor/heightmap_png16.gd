extends RefCounted
## Raw grayscale samples, independent of Image's color/8-bit conversion path.
## PNG third edition: https://www.w3.org/TR/png-3/ (chunks, filters, byte order).
const DIMENSIONS=[17,33,65,129,257,513]
static func fail(message:String)->Dictionary:return {"ok":false,"code":"heightmap_format_unsupported","error":message}
static func big32(b:PackedByteArray,i:int)->int:return (int(b[i])<<24)|(int(b[i+1])<<16)|(int(b[i+2])<<8)|int(b[i+3])
static func crc32(bytes:PackedByteArray)->int:
	var crc:=0xffffffff
	for byte in bytes:
		crc^=byte
		for bit in 8:crc=(crc>>1)^ (0xedb88320 if crc&1 else 0)
	return crc^0xffffffff
static func paeth(a:int,b:int,c:int)->int:
	var p:=a+b-c;var pa:=absi(p-a);var pb:=absi(p-b);var pc:=absi(p-c)
	return a if pa<=pb and pa<=pc else (b if pb<=pc else c)
static func decode(bytes:PackedByteArray)->Dictionary:
	if bytes.size()>4*1024*1024 or bytes.size()<33 or bytes.slice(0,8).hex_encode()!="89504e470d0a1a0a":return fail("需要预算内有效的 PNG16 文件")
	var at:=8;var width:=0;var height:=0;var data:=PackedByteArray();var ended:=false;var idat_seen:=false;var idat_closed:=false
	while at<bytes.size():
		if at+12>bytes.size():return fail("PNG 块头或校验被截断")
		var length:=big32(bytes,at);var end:=at+12+length
		if end>bytes.size():return fail("PNG 块长度超出文件")
		var type:=bytes.slice(at+4,at+8).get_string_from_ascii()
		for ch in bytes.slice(at+4,at+8):
			if not (ch>=65 and ch<=90 or ch>=97 and ch<=122):return fail("PNG 块类型无效")
		if bytes[at+6]&32:return fail("PNG 保留位无效")
		if crc32(bytes.slice(at+4,end-4))!=big32(bytes,end-4):return fail("PNG 块 CRC 校验失败")
		if at==8 and type!="IHDR":return fail("PNG 首块必须是 IHDR")
		if type=="IHDR":
			if at!=8 or length!=13:return fail("PNG 头重复或长度无效")
			width=big32(bytes,at+8);height=big32(bytes,at+12)
			if width not in DIMENSIONS or height not in DIMENSIONS:return fail("PNG 宽高须为 17、33、65、129、257 或 513")
			if bytes[at+16]!=16 or bytes[at+17]!=0:return fail("PNG16 仅接受 16 位单通道灰度，不接受彩色、调色板或透明通道")
			if bytes[at+18]!=0 or bytes[at+19]!=0 or bytes[at+20]!=0:return fail("PNG16 仅支持标准压缩／滤波和非交错扫描；请导出非 Adam7 PNG")
		elif type=="IDAT":
			if idat_closed:return fail("PNG IDAT 块必须连续")
			idat_seen=true;data.append_array(bytes.slice(at+8,end-4))
		else:
			if idat_seen:idat_closed=true
			if type=="IEND":
				if length!=0 or end!=bytes.size() or not idat_seen:return fail("PNG 结束块、尾部或图像数据无效")
				ended=true
			elif type in ["tRNS","acTL","fcTL","fdAT"]:return fail("高度图不接受透明或动画语义")
			elif not bytes[at+4]&32:return fail("PNG 含不支持的关键块："+type)
		at=end
	if not ended or data.size()<6:return fail("PNG 图像或结束块缺失")
	# Strict output cap is derived from checked dimensions, never from compressed input.
	if data[0]&15!=8 or data[0]>>4>7 or (int(data[0])*256+int(data[1]))%31!=0 or data[1]&32:return fail("PNG zlib 头无效")
	var stride:=width*2;var expected:=(stride+1)*height
	var raw:=data.decompress(expected,FileAccess.COMPRESSION_DEFLATE)
	if raw.size()!=expected:return fail("PNG 解压长度或压缩流无效")
	var values:Array=[];values.resize(width*height);var previous:=PackedByteArray();previous.resize(stride)
	for z in height:
		var filter:int=raw[z*(stride+1)]
		if filter>4:return fail("PNG 使用未知行滤波器")
		var row:=PackedByteArray();row.resize(stride)
		for x in stride:
			var a:int=row[x-2] if x>=2 else 0;var b:int=previous[x];var c:int=previous[x-2] if x>=2 else 0;var predictor:=0
			match filter:
				1:predictor=a
				2:predictor=b
				3:predictor=(a+b)/2
				4:predictor=paeth(a,b,c)
			row[x]=(int(raw[z*(stride+1)+1+x])+predictor)&255
		for x in width:values[z*width+x]=((int(row[x*2])<<8)|int(row[x*2+1]))/65535.
		previous=row
	return {"ok":true,"width":width,"height":height,"values":values,"bits":16}
