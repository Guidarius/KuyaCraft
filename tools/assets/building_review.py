"""Compose the reopened Blender views into local, untracked building review sheets."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
review=ROOT/'artifacts/building-review'
records=json.loads((review/'verification.json').read_text())
labels={'orbital_command':'ORBITAL COMMAND','mc_barracks':'BARRACKS','requisition_office':'REQUISITION OFFICE',
        'med_bay':'MED BAY','armory':'ARMORY','orbital_relay':'ORBITAL RELAY','substrate_rig':'SUBSTRATE RIG',
        'charge_rig':'CHARGE RIG','bunker':'BUNKER'}
title=ImageFont.load_default(size=28);label=ImageFont.load_default(size=19);small=ImageFont.load_default(size=16)
for view in ('assembly','game'):
    sheet=Image.new('RGBA',(1200,1170),'#dcded9');draw=ImageDraw.Draw(sheet)
    draw.text((35,20),'MEGACORP / BUILT MODELS',fill='#20272b',font=title)
    draw.text((35,58),'Editable low-poly modules / '+('assembly view' if view=='assembly' else '60-degree gameplay camera')+
              ' / panels shown in blue',fill='#454e53',font=small)
    for i,record in enumerate(records):
        x=(i%3)*400;y=90+(i//3)*360;unit=record['unit']
        with Image.open(review/(unit+'-'+view+'.png')) as source:
            thumb=source.convert('RGBA').resize((350,350),Image.Resampling.LANCZOS)
            sheet.alpha_composite(thumb,(x+25,y-12))
        draw.text((x+20,y+309),labels[unit],fill='#20272b',font=label)
        draw.text((x+20,y+337),str(record['footprintCells'])+'x'+str(record['footprintCells'])+' cells  /  '+
                  str(record['triangles'])+' triangles',fill='#454e53',font=small)
    sheet.convert('RGB').save(review/('megacorp-buildings-'+view+'.png'))
links=['# Megacorp buildings — local editable scenes','']
for record in records:
    unit=record['unit'];path=ROOT/'artifacts/asset-build'/record['buildId']/unit/(unit+'.blend')
    links.append('- ['+labels[unit]+']('+path.as_posix()+')')
(review/'MODELS.md').write_text('\n'.join(links)+'\n',encoding='utf8')
print('Building review sheets and editable-scene links:',review)
