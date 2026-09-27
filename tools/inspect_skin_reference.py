"""Extract embedded source images from the user-provided UE4 skin reference.
Keeps source assets untouched; validates compressed chunks and decoded images.
"""
from pathlib import Path
import io,json,re,struct,zlib
from PIL import Image
from art_paths import art_path
root=art_path('characters/source_models/templar_skin_reference')
content=root/'TemplarKnight_UE4/Content/TemplarKnight'
out=root/'extracted_skin_maps';out.mkdir(exist_ok=True)
signature=b'\x89PNG\r\n\x1a\n'
magic=struct.pack('<Q',0x9e2a83c1)
report={}
for folder in ['Face','SkinDetail']:
    for source in (content/'Textures'/folder).glob('*.uasset'):
        blob=source.read_bytes();candidates=[]
        for match in re.finditer(re.escape(signature),blob):
            start=match.start();cursor=start+8
            while cursor+12<=len(blob):
                size=struct.unpack_from('>I',blob,cursor)[0];kind=blob[cursor+4:cursor+8]
                if cursor+12+size>len(blob):break
                data=blob[cursor+8:cursor+8+size]
                if zlib.crc32(kind+data)&0xffffffff!=struct.unpack_from('>I',blob,cursor+8+size)[0]:break
                cursor+=12+size
                if kind==b'IEND':candidates.append(blob[start:cursor]);break
        for match in re.finditer(re.escape(magic),blob):
            start=match.start()
            if start+32>len(blob):continue
            _,chunk_size,compressed,uncompressed=struct.unpack_from('<QQQQ',blob,start)
            if chunk_size!=131072 or not 0<uncompressed<300_000_000:continue
            count=(uncompressed+chunk_size-1)//chunk_size
            if start+32+count*16+compressed>len(blob):continue
            table=[struct.unpack_from('<QQ',blob,start+32+i*16) for i in range(count)]
            if sum(c for c,u in table)!=compressed or sum(u for c,u in table)!=uncompressed:continue
            cursor=start+32+count*16;pieces=[]
            for c,u in table:
                raw=zlib.decompress(blob[cursor:cursor+c]);assert len(raw)==u
                pieces.append(raw);cursor+=c
            candidates.append(b''.join(pieces))
        images=[]
        for data in candidates:
            try:
                picture=Image.open(io.BytesIO(data));picture.verify()
                picture=Image.open(io.BytesIO(data));images.append((picture.width*picture.height,picture,data))
            except (OSError,ValueError):continue
        if not images:continue
        _,picture,data=max(images,key=lambda item:item[0])
        source_formats=set(re.findall(rb'TSF_[A-Za-z0-9]+',blob))
        # UE4's BGRA8 source payload and thumbnail PNGs store B/R in
        # source-memory order. RGBA16 assets use their native RGB order.
        if source_formats=={b'TSF_BGRA8'}:
            channels=picture.convert('RGBA').split()
            picture=Image.merge('RGBA',(channels[2],channels[1],channels[0],channels[3]))
        picture.save(out/(source.stem+'.png'))
        report[source.stem]={'source':str(source.relative_to(root)),'size':list(picture.size),'mode':picture.mode,'thumbnail_only':max(picture.size)<=256,'source_formats':[v.decode() for v in source_formats],'preview_bit_depth':8}
materials={}
for source in (content/'Materials').rglob('*.uasset'):
    if source.stem not in ['M_Skin','M_TK_Skin','M_TK_Face','TK_Skin']:continue
    strings=[v.decode('ascii').rstrip('\0') for v in re.findall(rb'[\x20-\x7e]{5,}\x00',source.read_bytes())]
    materials[str(source.relative_to(content))]=[v for v in strings if any(k in v.lower() for k in ['rough','normal','subsurface','skin','color','specular','detail','scatter'])]
report['material_identifiers']=materials
(out/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
for k,v in report.items():
    if k!='material_identifiers':print(k,v['size'],'THUMBNAIL' if v['thumbnail_only'] else 'SOURCE')
