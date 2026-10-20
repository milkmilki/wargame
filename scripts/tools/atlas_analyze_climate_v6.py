"""Offline climate validation. Requires numpy, h5py and Pillow; never imported by the game.

GPCP v2.3 1991-2020, NOAA PSL: monthly rates (mm/day) -> seasonal totals.
Actual coordinate arrays, rather than the reversed actual_range attribute, define orientation.
"""
import argparse,pathlib,json,hashlib
ROOT=pathlib.Path(__file__).resolve().parents[2]
import numpy as np,h5py
from PIL import Image,ImageDraw,ImageFont
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=pathlib.Path,default=ROOT/'.dbg/climate-v6')
parser.add_argument('--reference',type=pathlib.Path)
parser.add_argument('--font',default='C:/Windows/Fonts/msyh.ttc')
parser.add_argument('--previous',type=pathlib.Path,help='Previous v6 export directory, for a same-model before/after comparison')
parser.add_argument('--write-reference-fixture',action='store_true',help='Regenerate test-only observed grid and regional summaries')
args=parser.parse_args();OUT=args.output;FONT=args.font
PREVIOUS=args.previous
REFERENCE=args.reference or OUT/'reference/gpcp-precip-1991-2020.nc'
ZONES={
 'Amazon':[-75,-50,-10,5],'Congo':[15,30,-5,5],'MaritimeSEA':[95,140,-10,10],
 'Sahara':[-10,30,20,30],'Arabia':[40,55,18,30],'Gobi':[95,110,38,47],
 'CentralAsia':[55,85,38,48],'AustraliaInterior':[120,140,-30,-20],'Atacama':[-72,-68,-28,-18],
 'WesternEurope':[-10,10,45,58],'Mediterranean':[-10,30,35,43],'EasternUS':[-95,-75,30,45],
 'India':[72,88,10,28],'SouthChina':[105,122,22,34],'NorthChina':[110,122,34,42],
 'Japan':[130,145,30,45],'PacificNW':[-126,-120,42,52],'Patagonia':[-74,-65,-50,-40],
 'Siberia':[80,130,55,65], 'Eurasia':[-15,145,20,55],
 'EastAfrica':[30,50,-10,12], 'EquatorialEastAfrica':[35,42,-5,5], 'HornLowlands':[40,51,-2,12],
}
lon,lat=np.meshgrid(np.arange(360)-179.5,89.5-np.arange(180))
land=np.fromfile(OUT/'land.bin',dtype='u1').reshape(180,360)>0
elevation=np.fromfile(OUT/'elevation.bin',dtype='<f4').reshape(180,360)
weight=np.cos(np.radians(lat))*land
def field(name):
    path=PREVIOUS/(name.replace('previous-','after-',1)+'.bin') if PREVIOUS and name.startswith('previous-') else OUT/(name+'.bin')
    return np.fromfile(path,dtype='<f4').reshape(180,360)
def regrid(values,lons,lats):
    # Read coordinate arrays: GPCP's actual_range attribute is descending,
    # but this file's latitude coordinates and data are ascending.
    if lats[0]<lats[-1]:values=values[...,::-1,:];lats=lats[::-1]
    xx=(np.mod(lon,360)-lons[0])/(lons[1]-lons[0]);yy=(lats[0]-lat)/(lats[0]-lats[1])
    x=np.floor(xx).astype(int);y=np.clip(np.floor(yy).astype(int),0,70)
    fx=xx-x;fy=np.clip(yy-y,0,1)
    return (values[...,y,x%144]*(1-fx)*(1-fy)+values[...,y,(x+1)%144]*fx*(1-fy)+values[...,y+1,x%144]*(1-fx)*fy+values[...,y+1,(x+1)%144]*fx*fy)
with h5py.File(REFERENCE) as f:
    assert f['precip'].attrs['units']==b'mm/day'
    raw=f['precip'][:];monthly=regrid(raw,f['lon'][:],f['lat'][:])
    coarse_monthly=raw[:,::-1,:] if f['lat'][0]<f['lat'][-1] else raw
days=np.array([31,28.25,31,30,31,30,31,31,30,31,30,31])
obs_annual=np.sum(monthly*days[:,None,None],axis=0)
obs_quarters=np.stack([np.sum(monthly[months]*days[months,None,None],axis=0) for months in [[11,0,1],[2,3,4],[5,6,7],[8,9,10]]])
def average(x,mask):
    w=weight*mask
    return float(np.sum(x*w)/np.sum(w))
def metrics(label):
    annual=field(label+'-annual');q=np.stack([field(label+f'-rain-{q}')*.25 for q in range(4)])
    valid=(abs(lat)<75)&land
    regions={}
    for k,(x0,x1,y0,y1) in ZONES.items():
        m=(lon>=x0)&(lon<x1)&(lat>=y0)&(lat<y1)&valid
        if k=='HornLowlands':m &= elevation<800
        regions[k]={'model_mm':round(average(annual,m),1),'observed_mm':round(average(obs_annual,m),1),
                    'model_quarters_mm':[round(average(a,m),1) for a in q],
                    'observed_quarters_mm':[round(average(a,m),1) for a in obs_quarters]}
    result={'mae_mm':average(abs(annual-obs_annual),valid),'log_mae':average(abs(np.log1p(annual)-np.log1p(obs_annual)),valid),
            'seasonal_mae_mm':sum(average(abs(a-b),valid) for a,b in zip(q,obs_quarters))/4,
            'mean_mm':average(annual,valid),'observed_mean_mm':average(obs_annual,valid),'regions':regions}
    (OUT/(label+'-metrics.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(label,{k:round(v,3) for k,v in result.items() if k!='regions'})
    for k,r in regions.items():print(k,r)
    return result

PALETTE=['#a7835e','#dab777','#ece3a0','#b4d477','#63b686','#329dab','#277caa','#344ea2','#5e3288']
BREAKS=[100,250,500,750,1000,1500,2000,3000]
def rain_image(value):
    colors=np.array([tuple(bytes.fromhex(c[1:])) for c in PALETTE],dtype='u1')
    rgb=colors[np.digitize(value,BREAKS)];rgb[~land]=[20,38,55]
    return Image.fromarray(rgb).resize((1080,540),Image.Resampling.NEAREST)
def render(labels):
    canvas=Image.new('RGB',(1140,112+len(labels)*590+90),'#0c1723');draw=ImageDraw.Draw(canvas)
    ft=lambda n:ImageFont.truetype(FONT,n)
    draw.text((30,12),'真实地球年降水分布 · 观测与模拟',font=ft(28),fill='white')
    draw.text((30,57),'观测：NOAA GPCP v2.3，1991–2020；模拟：地球种子1，1°气候网格',font=ft(18),fill='#acc1cf')
    for i,(title,field_value) in enumerate(labels):
        y=112+i*590;draw.text((30,y),title,font=ft(22),fill='white');canvas.paste(rain_image(field_value),(30,y+35))
    y=canvas.height-72
    for i,(c,text) in enumerate(zip(PALETTE,['<100','100–250','250–500','500–750','750–1000','1000–1500','1500–2000','2000–3000','≥3000'])):
        x=30+i*120;draw.rectangle((x,y,x+112,y+20),fill=c);draw.text((x,y+23),text,font=ft(13),fill='white')
    draw.text((30,y+48),'单位：毫米/年。仅比较共同陆地区域；海洋隐藏。',font=ft(16),fill='#acc1cf')
    canvas.save(OUT/('rainfall-comparison.png' if len(labels)>2 else 'baseline-comparison.png'))

def render_seasons_and_storage():
    if not (OUT/'after-rain-0.bin').exists():return
    ft=lambda n:ImageFont.truetype(FONT,n)
    canvas=Image.new('RGB',(1140,1980),'#0c1723');draw=ImageDraw.Draw(canvas)
    draw.text((30,12),'季节雨量差 · 北半球夏季减冬季',font=ft(28),fill='white')
    draw.text((30,58),'同一差值色标；蓝色偏夏雨，棕色偏冬雨。单位：毫米/季度。',font=ft(18),fill='#acc1cf')
    colors=np.array([[145,91,49],[194,145,86],[229,201,159],[225,229,225],[153,198,210],[73,147,182],[35,77,133]],dtype='u1')
    values=[obs_quarters[2]-obs_quarters[0]]+[.25*(field(label+'-rain-2')-field(label+'-rain-0')) for label in ['previous' if PREVIOUS else 'before','after']]
    for i,(title,value) in enumerate(zip(['GPCP 1991–2020','修改前 v6' if PREVIOUS else '修改前 v5','改进后 v6'],values)):
        y=112+i*590;draw.text((30,y),title,font=ft(22),fill='white')
        rgb=colors[np.digitize(value,[-600,-250,-75,75,250,600])];rgb[~land]=[20,38,55]
        canvas.paste(Image.fromarray(rgb).resize((1080,540),Image.Resampling.NEAREST),(30,y+35))
    for i,(c,label) in enumerate(zip(colors,['<−600','−600~−250','−250~−75','−75~75','75~250','250~600','≥600'])):
        x=30+i*154;draw.rectangle((x,1900,x+145,1920),fill=tuple(c));draw.text((x,1925),label,font=ft(16),fill='white')
    canvas.save(OUT/'seasonal-comparison.png')
    if not (OUT/'after-forest_cover.bin').exists():return
    canvas=Image.new('RGB',(1140,1390),'#0c1723');draw=ImageDraw.Draw(canvas)
    draw.text((30,12),'有限根区蓄水与潜在森林覆盖',font=ft(28),fill='white')
    draw.text((30,58),'覆盖由模拟水热条件推断；土壤水以先前降雨为来源，不是实测森林或土壤地图。',font=ft(18),fill='#acc1cf')
    colors=np.array([[225,215,169],[187,203,131],[124,177,112],[67,145,104],[31,103,90]],dtype='u1')
    panels=[('潜在森林覆盖 · 0~100%',field('after-forest_cover'),[.2,.4,.6,.8]),
            ('JJA 季末根区水量 · 0~300 毫米',field('after-soil_moisture-2'),[30,75,150,225])]
    for i,(title,value,breaks) in enumerate(panels):
        y=112+i*620;draw.text((30,y),title,font=ft(22),fill='white')
        rgb=colors[np.digitize(value,breaks)];rgb[~land]=[20,38,55]
        canvas.paste(Image.fromarray(rgb).resize((1080,540),Image.Resampling.NEAREST),(30,y+35))
        labels=['0~20%','20~40%','40~60%','60~80%','80~100%'] if i==0 else ['0~30','30~75','75~150','150~225','225~300']
        for k,label in enumerate(labels):
            x=30+k*215;draw.rectangle((x,y+580,x+40,y+602),fill=tuple(colors[k]));draw.text((x+48,y+580),label,font=ft(16),fill='white')
    draw.text((30,1352),'地表水收支闭合；简化大气输送并非全球质量守恒的数值气候模式。',font=ft(18),fill='#acc1cf')
    canvas.save(OUT/'forest-storage.png')

if __name__=='__main__':
    labels=[('真实观测 · GPCP 1991–2020',obs_annual)]
    reference={'source_url':'https://psl.noaa.gov/thredds/fileServer/Datasets/gpcp/precip.mon.ltm.1991-2020.nc',
               'source_sha256':hashlib.sha256(REFERENCE.read_bytes()).hexdigest(),'version':'GPCP v2.3','period':'1991-2020',
               'resolution_degrees':2.5,'units':'mm; calendar-day-weighted quarterly totals',
               'comparison':'bilinear 1 degree reference; common source land mask, cosine latitude area weights; no observed rainfall in runtime',
               'regions':{}}
    for name,b in ZONES.items():
        m=(lon>=b[0])&(lon<b[1])&(lat>=b[2])&(lat<b[3])&land
        if name=='HornLowlands':m &= elevation<800
        reference['regions'][name]={'bounds_west_east_south_north':b,'annual_mm':average(obs_annual,m),
                                    'quarter_mm':[average(q,m) for q in obs_quarters]}
        if name=='HornLowlands':reference['regions'][name]['max_elevation_m']=800
    (OUT/'reference-regions.json').write_text(json.dumps(reference,indent=2),encoding='utf-8')
    results={}
    for label in ['before']+(['previous'] if PREVIOUS else [])+['after']:
        if label=='previous' or (OUT/(label+'-annual.bin')).exists():
            results[label]=metrics(label)
            if label=='before' and PREVIOUS:continue
            labels.append(('修改前 v6' if label=='previous' else '修改前 v5' if label=='before' else '改进后 v6',field(label+'-annual')))
    if args.write_reference_fixture:
        fixture=ROOT/'tests/fixtures/atlas_climate_reference.json'
        existing=json.loads(fixture.read_text(encoding='utf-8'))
        coarse_quarters=np.stack([np.sum(coarse_monthly[months]*days[months,None,None],axis=0) for months in [[11,0,1],[2,3,4],[5,6,7],[8,9,10]]]).astype('<f4').tobytes()
        (fixture.parent/'atlas_climate_gpcp_quarters.f32').write_bytes(coarse_quarters)
        reference['grid_reference']=existing['grid_reference'];reference['grid_reference']['sha256']=hashlib.sha256(coarse_quarters).hexdigest()
        for key in ['baseline_model','baseline_region_annual_mae_mm','baseline_region_quarter_mae_mm','revision1_global_annual_mae_mm','revision1_global_quarter_mae_mm']:reference[key]=existing[key]
        fixture.write_text(json.dumps(reference,indent=2)+'\n',encoding='utf-8')
    render(labels)
    render_seasons_and_storage()
