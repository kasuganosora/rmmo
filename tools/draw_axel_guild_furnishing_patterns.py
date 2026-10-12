"""Authored graphic patterns for model materials; no screenshot pixels copied.

Original illegible ornaments retain layout but do not purport to translate canon.
These are UV material graphics, not generated illustrations or game UI text.
"""
from pathlib import Path
from PIL import Image,ImageDraw
import random
import json
OUT=Path(__file__).resolve().parents[2]/'rmmo_runtime/art_sources/axel_guild/furnishings_v1/textures'
OUT.mkdir(parents=True,exist_ok=True)

def glyph(d,x,y,s,color,index):
 pts=[(x,y),(x+s*.4,y-s*.6),(x+s*.8,y),(x+s*.4,y+s*.6),(x,y)]
 if index%3==0:d.line(pts,fill=color,width=max(1,int(s*.13)))
 elif index%3==1:d.line([(x,y+s*.6),(x,y-s*.6),(x+s*.65,y-s*.6),(x+s*.4,y),(x+s*.8,y+s*.6)],fill=color,width=max(1,int(s*.13)))
 else:d.line([(x,y-s*.6),(x+s*.8,y-s*.6),(x+s*.4,y),(x+s*.8,y),(x+s*.8,y+s*.6),(x,y+s*.6)],fill=color,width=max(1,int(s*.13)))

atlas=Image.new('RGB',(1024,1536));d=ImageDraw.Draw(atlas)
for i in range(16):
 x=i%4*256;y=i//4*384;r=random.Random(514+i)
 color=(r.randint(208,222),r.randint(190,203),r.randint(154,175))
 d.rectangle((x,y,x+255,y+383),fill=color)
 d.rectangle((x+10,y+10,x+245,y+373),outline=(155,132,98),width=2)
 for j in range(9):glyph(d,x+26+j*23,y+39,15,(75,64,49),i+j)
 # Distinct simple mission emblems: crossed blades, animal track, eye, compass.
 cx,cy=x+128,y+106;ink=(81,68,49)
 if i%4==0:
  for sign in [-1,1]:d.polygon([(cx-sign*43,cy+33),(cx+sign*29,cy-37),(cx+sign*42,cy-46),(cx+sign*37,cy-29),(cx-sign*31,cy+41)],fill=ink)
 elif i%4==1:
  d.ellipse((cx-24,cy-4,cx+24,cy+34),outline=ink,width=4)
  for dx,dy in [(-33,-15),(-12,-29),(12,-29),(33,-15)]:d.ellipse((cx+dx-7,cy+dy-10,cx+dx+7,cy+dy+10),fill=ink)
 elif i%4==2:
  d.polygon([(cx-52,cy),(cx,cy-31),(cx+52,cy),(cx,cy+31)],outline=ink,width=4);d.ellipse((cx-17,cy-17,cx+17,cy+17),outline=ink,width=4)
 else:
  d.ellipse((cx-31,cy-31,cx+31,cy+31),outline=ink,width=3)
  d.line((cx-48,cy,cx+48,cy),fill=ink,width=4);d.line((cx,cy-48,cx,cy+48),fill=ink,width=4)
 for line in range(13):
  yy=y+169+line*12
  for j in range(r.randint(13,18)):glyph(d,x+24+j*12,yy,7,(94,81,63),r.randrange(9))
 if i%3!=1:
  cx=x+194;cy=y+326
  d.ellipse((cx-22,cy-22,cx+22,cy+22),outline=(141,48,37),width=4)
  d.ellipse((cx-16,cy-16,cx+16,cy+16),outline=(141,48,37),width=2)
  glyph(d,cx-6,cy,14,(141,48,37),i)
atlas.save(OUT/'quest_paper_atlas.png')

notice=Image.new('RGB',(512,1024),(221,210,175));d=ImageDraw.Draw(notice)
d.rounded_rectangle((17,17,495,1007),radius=45,outline=(108,104,80),width=4)
for row in range(29):
 for j in range(20):glyph(d,40+j*21,68+row*31,12,(85,83,67),j+row)
notice.save(OUT/'notice_pattern.png')

strip=Image.new('RGB',(1024,128),(73,35,29));d=ImageDraw.Draw(strip)
for i in range(22):glyph(d,31+i*44,64,32,(172,149,76),i+2)
strip.save(OUT/'ornament_strip.png')

rug=Image.new('RGB',(768,1792),(40,66,62));d=ImageDraw.Draw(rug)
for inset,width in [(15,9),(39,3),(96,4),(116,2)]:d.rectangle((inset,inset,767-inset,1791-inset),outline=(169,178,142),width=width)
for y in range(140,1700,92):
 for x in [65,703]:
  d.polygon([(x,y-29),(x+20,y),(x,y+29),(x-20,y)],outline=(162,176,143),width=3)
  d.line((x,y-19,x,y+19),fill=(162,176,143),width=2)
for x in range(145,680,92):
 for y in [67,1725]:d.polygon([(x-29,y),(x,y+20),(x+29,y),(x,y-20)],outline=(162,176,143),width=3)
for y in range(210,1640,170):
 d.polygon([(384,y-45),(411,y),(384,y+45),(357,y)],outline=(91,120,101),width=2)
rug.save(OUT/'runner_pattern.png')
(OUT/'patterns.json').write_text(json.dumps({'authored':True,'reference_layouts':['U02','U09','U12'],
 'no_screenshot_pixels':True,'glyphs':'original decorative marks, no translated or readable quest text',
 'paper_atlas':'4 x 4, 16 replaceable graphic tiles','rug':'authored border motif following U02 layout'},indent=2),encoding='utf8')
print('FURNISHING_PATTERNS_READY')
