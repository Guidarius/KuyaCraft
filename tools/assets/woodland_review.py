"""Dense full-loop contact sheets, one row per direction, with a wrap sample."""
import argparse
from pathlib import Path
from PIL import Image,ImageDraw
from woodland_edit import metadata,frames
def review(root,output):
    output.mkdir(parents=True,exist_ok=True)
    for height in (32,48,64):
        m=metadata(root,height);all_frames=list(frames(root,m))
        for clip in m['clips']:
            groups={d:[] for d in m['directions']}
            for key,images,_ in all_frames:
                _,c,d,n=key.split('/')
                if c==clip:groups[d].append(images[0])
            size=height*3;count=len(groups['S']);sheet=Image.new('RGBA',((count+1)*size,8*(size+18)),(75,83,61,255))
            draw=ImageDraw.Draw(sheet)
            for row,(d,images) in enumerate(groups.items()):
                for col,im in enumerate(images+[images[0]]):
                    x=col*size;y=row*(size+18)
                    sheet.alpha_composite(im,(x,y+18));draw.text((x+3,y+2),f'{d} {col+1 if col<count else "wrap"}',fill='white')
            sheet.save(output/f'{height}-{clip}-loop.png')
    print('Loop sheets: '+str(output))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2]);p.add_argument('--output',type=Path,default=Path('artifacts/woodland/review'))
    a=p.parse_args();review(a.root,a.output)
