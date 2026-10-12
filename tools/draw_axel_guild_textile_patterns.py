"""Original repeatable embroidered motifs, not screenshot pixels or copied text."""
from pathlib import Path
import math,json
import numpy as np
from PIL import Image,ImageDraw
OUT=Path('D:/code/rmmo_runtime/art_sources/axel_guild/textiles_sanitary_v1/textures');OUT.mkdir(parents=True,exist_ok=True)
def floral(draw,x,y,r,color):
    for i in range(8):
        a=i*math.tau/8
        p=[(x,y),(x+r*.75*math.cos(a-.15),y+r*.75*math.sin(a-.15)),(x+r*math.cos(a),y+r*math.sin(a)),(x+r*.75*math.cos(a+.15),y+r*.75*math.sin(a+.15))]
        draw.polygon(p,fill=color)
    draw.ellipse((x-r*.15,y-r*.15,x+r*.15,y+r*.15),fill=(176,140,68))
for name,w,h,base in [('tapestry',1536,2048,(48,57,49)),('banner',768,2048,(103,37,35))]:
    im=Image.new('RGB',(w,h),base);d=ImageDraw.Draw(im);gold=(167,135,75);cream=(170,161,132);rust=(112,51,40)
    for pad,stroke in [(20,8),(43,3),(92,4),(112,3)]:d.rectangle((pad,pad,w-pad,h-pad),outline=gold,width=stroke)
    for y in range(150,h-120,95):
        for x in [67,w-67]:
            d.polygon([(x,y-28),(x+17,y),(x,y+28),(x-17,y)],outline=gold,width=3)
    if name=='tapestry':
        for j,y in enumerate(range(280,h-180,360)):
            for x in range(310,w-120,450):
                d.polygon([(x,y-135),(x+160,y),(x,y+135),(x-160,y)],outline=gold,width=10)
                d.polygon([(x,y-108),(x+130,y),(x,y+108),(x-130,y)],outline=cream,width=3)
                floral(d,x,y,78,rust if j%2 else gold)
                for dx in [-195,195]:floral(d,x+dx,y+160,36,cream)
    else:
        # Vine stem and paired leaves, with a heraldic star; no literal writing.
        cx=w//2;d.line((cx,270,cx,h-240),fill=gold,width=7)
        for y in range(380,h-280,180):
            for side in [-1,1]:
                d.line((cx,y+60,cx+side*150,y-50),fill=gold,width=5)
                d.polygon([(cx+side*75,y+5),(cx+side*160,y-75),(cx+side*180,y-40),(cx+side*123,y+7)],fill=cream)
        floral(d,cx,230,105,gold)
    a=np.asarray(im).astype(float);rng=np.random.default_rng(402)
    yy,xx=np.mgrid[0:h,0:w];weave=(np.sin(xx*math.pi)*.4+np.cos(yy*math.pi)*1.5+np.sin(xx*.18)*.6)
    a=np.clip(a+weave[:,:,None]+rng.normal(0,1.15,(h,w,1)),0,255).astype('uint8')
    Image.fromarray(a).save(OUT/(name+'_pattern.png'))
(OUT/'patterns.json').write_text(json.dumps({'source':'Original procedural floral/diamond/vine arrangement inspired by U04/U07 layout; not a literal emblem reconstruction','screenshots_sampled':False,'generator':'tools/draw_axel_guild_textile_patterns.py'},indent=2),encoding='utf8')
print('TEXTILE_PATTERNS_READY')
