from pathlib import Path
from PIL import Image,ImageDraw
base=Path('D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013')
out=base/'independent_library_review/accepted_contact_sheets'
out.mkdir(exist_ok=True)
for folder in (base/'accepted_library').iterdir():
 if not (folder/'report.json').exists():continue
 paths=[folder/(v+'_still.png') for v in ['near','back','highlight','medium','far']]
 paths += [p for p in sorted(folder.glob('*.png')) if p not in paths]
 target=out/(folder.name+'.jpg')
 if target.exists() and target.stat().st_mtime>=max(p.stat().st_mtime for p in paths):continue
 canvas=Image.new('RGB',(1800,385*((len(paths)+2)//3)),(31,34,36));draw=ImageDraw.Draw(canvas)
 for i,path in enumerate(paths):
  im=Image.open(path).convert('RGB');im.thumbnail((600,352))
  x=(i%3)*600;y=(i//3)*385
  canvas.paste(im,(x+(600-im.width)//2,y+27+(352-im.height)//2))
  draw.text((x+8,y+7),folder.name+' / '+path.stem,fill='white')
 canvas.save(target,quality=94)
print('contacts',len(list(out.glob('*.jpg'))))
