/** Browser reference images only; not shipped or invoked by Godot. */
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const root=path.resolve(process.argv[2]), out=path.resolve(process.argv[3]);
const {createServer}=await import(pathToFileURL(path.join(root,'node_modules/vite/dist/node/index.js')).href);
const {chromium}=await import(pathToFileURL(path.join(root,'node_modules/playwright/index.mjs')).href);
// Freeze historical titles only in this developer reference. Label algorithms remain upstream.
const staticTitles={name:'atlas-static-titles',enforce:'pre' as const,transform(code:string,id:string){
 if(!id.replace(/\\/g,'/').endsWith('/src/gen/civ/growth.ts'))return null;
 for(const [name,body] of [['polityName','return p.name;'],['polityShortTitle','return p.name;'],['polityAllTitles','return [p.name];']]){
  const at=code.indexOf('export function '+name+'(');if(at<0)throw new Error('Missing static title adapter '+name);
  const start=code.indexOf('{',at);let depth=1,end=start+1;while(depth&&end<code.length){if(code[end]==='{')depth++;if(code[end]==='}')depth--;end++;}
  code=code.slice(0,start+1)+body+code.slice(end-1);
 }
 return code;
}};
const server=await createServer({root,plugins:[staticTitles],configFile:false,logLevel:'error',server:{port:0,host:'127.0.0.1'}});
await server.listen();
const port=(server.httpServer!.address() as any).port;
const browser=await chromium.launch({headless:true});
const markup=`<!doctype html><canvas id="terrain" width="2048" height="1024"></canvas>
<canvas id="political" width="2048" height="1024"></canvas><script type="module">
import {generateWorld} from '/src/gen/world.ts';
import {rasterize} from '/src/gen/raster.ts';
import {renderFantasy,planGlyphs,fantasyCoastLines,seaRippleLines,iceLines,DIST_Q} from '/src/render/fantasy.ts';
import {distanceTo} from '/src/render/common.ts';
import {drawCivOverlay} from '/src/render/civ/overlay.ts';
import {borderLines} from '/src/render/civ/borders.ts';
import {regionPixels,washFields} from '/src/render/civ/territory.ts';
import {drawTerrainDetail} from '/src/render/detail.ts';
import {drawCivDetail,detailCache} from '/src/render/civ/detail.ts';
import {habitatCanvas} from '/src/render/civ/debug.ts';
import {createNamer} from '/src/gen/names/index.ts';
import {findPlaces} from '/src/gen/civ/places.ts';
import {civMapLayer,placeLabelItems} from '/src/render/civ/labels.ts';
import {placeMap,drawPlacedLabels} from '/src/render/labels/draw.ts';
import {drawSettlementMarks} from '/src/render/civ/settlements.ts';
import {ensureFonts} from '/src/render/labels/fonts.ts';
const data=await fetch('/native-world.json').then(r=>r.json());
const world=generateWorld(data.params);world.rivers=[];
const raster=rasterize(world,1,false);
const regionFields=['of','seat','cellStart','cells','adjStart','adj','landmass'];
for(const key of regionFields) data.regions[key]=Int32Array.from(data.regions[key]);
for(const key of ['adjKind','biome']) data.regions[key]=Uint8Array.from(data.regions[key]);
for(const key of ['adjLen','area','capacity','elevation','adjBorder']) data.regions[key]=Float32Array.from(data.regions[key]);
const nations=data.nations.map((n,i)=>({...n,id:i,color:hsv(n.hue,.36,.76)}));
function hsv(h,s,v){const f=n=>{let k=(n+h*6)%6;return Math.round((v-v*s*Math.max(0,Math.min(k,4-k,1)))*255)};return [f(5),f(3),f(1)]}
const owners=Int16Array.from(data.ownership);
const civ={seed:data.seed,endYear:0,regions:data.regions,routes:data.roads.map(r=>({...r,cells:Int32Array.from(r.cells)})),
 habitat:{suitability:Float32Array.from(data.environment.suitability)},
 settlements:data.cities,polities:nations,cultures:[],places:[],polity:owners,culture:new Int16Array(owners.length).fill(-1),
 log:{size:0,year:new Float32Array(),region:new Int32Array(),layer:new Uint8Array(),value:new Int16Array()},
 checkpoints:[{year:0,polity:owners,culture:new Int16Array(owners.length).fill(-1)}],annals:[]};
const show={habitat:false,regions:false,sites:false,routes:true,labels:false,cultures:false,polities:true,faiths:false,wars:false};
const p={world,raster,civ,year:0,style:'fantasy',show};
renderFantasy(document.querySelector('#terrain').getContext('2d'),world,raster);
const political=document.querySelector('#political').getContext('2d');
const overlay=document.createElement('canvas');overlay.width=2048;overlay.height=1024;
drawCivOverlay(overlay.getContext('2d'),p);
political.drawImage(document.querySelector('#terrain'),0,0);political.drawImage(overlay,0,0);
const extra={};
const habitatView=document.createElement('canvas');habitatView.width=2048;habitatView.height=1024;
habitatView.getContext('2d').drawImage(document.querySelector('#terrain'),0,0);habitatView.getContext('2d').drawImage(habitatCanvas(p),0,0);
const habitatInk=document.createElement('canvas');habitatInk.width=2048;habitatInk.height=1024;
drawCivOverlay(habitatInk.getContext('2d'),{...p,show:{...show,polities:false}});habitatView.getContext('2d').drawImage(habitatInk,0,0);extra.habitat=habitatView.toDataURL();
const provinceOwners=Int16Array.from({length:data.regions.count},(_,i)=>i);
const provinceCiv={...civ,polity:provinceOwners,polities:Array.from({length:data.regions.count},(_,i)=>({id:i,seat:i,name:'',color:hsv((i*.61803398875)%1,.36,.76)})),checkpoints:[{year:0,polity:provinceOwners,culture:civ.culture}]};
const provinceView=document.createElement('canvas');provinceView.width=2048;provinceView.height=1024;
const provinceInk=document.createElement('canvas');provinceInk.width=2048;provinceInk.height=1024;
provinceView.getContext('2d').drawImage(document.querySelector('#terrain'),0,0);drawCivOverlay(provinceInk.getContext('2d'),{...p,civ:provinceCiv});provinceView.getContext('2d').drawImage(provinceInk,0,0);extra.province=provinceView.toDataURL();
window.zoomImage=(k,cx,cy)=>{
 const terrain=document.createElement('canvas');terrain.width=2048;terrain.height=1024;
 const ctx=terrain.getContext('2d'),ox=1024-cx*k,oy=512-cy*k;
 for(const shift of [-2048,0,2048]){
  ctx.save();ctx.beginPath();ctx.rect(ox+shift*k,oy,2048*k,1024*k);ctx.clip();
  drawTerrainDetail(ctx,world,raster,'fantasy',{s:k,ox:ox+shift*k,oy,k,wrap:2048});ctx.restore();
 }
 const layer=document.createElement('canvas');layer.width=2048;layer.height=1024;
 drawCivDetail(layer.getContext('2d'),p,{s:k,ox,oy,cw:2048,ch:1024,k,dpr:1,mp:null},1,detailCache());
 ctx.drawImage(layer,0,0);return terrain.toDataURL();
};
window.namedImage=async(k,cx,cy)=>{
 const namer=createNamer(data.seed,'central'),taken=new Set();
 const name=(kind,cell)=>{const next=namer.keyed(kind,cell);let g=next();while(taken.has(g.zh))g=next();taken.add(g.zh);return g.zh;};
 for(let r=0;r<data.regions.count;r++)name('region',data.regions.seat[r]);
 const cities=data.cities.map((c,id)=>({...c,id,name:name('city',c.cell),culture:-1,founded:0,growth:0,capacity:41*(c.major?100:40)}));
 const polities=nations.map((n,id)=>({...n,id,founded:0,name:name('state',data.regions.seat[n.seat]),capital:cities.findIndex(c=>c.region===n.seat)}));
 const namedCiv={...civ,settlements:cities,polities,places:findPlaces(world,data.regions)};
 const namedP={...p,civ:namedCiv,show:{...show,labels:true}};
 const text=[...cities.map(c=>c.name),...polities.map(n=>n.name),...namedCiv.places.map(p=>p.name)].join('');
 await ensureFonts('fantasy',text);
 const layer=civMapLayer(namedP),view={scale:k,ox:1024-cx*k,oy:512-cy*k,dpr:1,k,mapCss:2048,worldW:2048,worldH:1024,canvasW:2048,canvasH:1024,wrap:2048,margin:0,surface:(x,y)=>y>=0&&y<1024?raster.water[Math.floor(y)*2048+((Math.floor(x)%2048)+2048)%2048]:-1};
 const placement=placeMap([...placeLabelItems(namedCiv.places,'fantasy'),...layer.items],layer.marks,view);
 const canvas=document.createElement('canvas');canvas.width=2048;canvas.height=1024;const ctx=canvas.getContext('2d'),img=new Image();
 await new Promise((ok,bad)=>{img.onload=ok;img.onerror=bad;img.src=window.zoomImage(k,cx,cy)});ctx.drawImage(img,0,0);
 drawSettlementMarks(ctx,placement.marks,'fantasy');drawPlacedLabels(ctx,placement.labels,view);return canvas.toDataURL();
};
const packed=(a)=>{const b=new Uint8Array(a.buffer,a.byteOffset,a.byteLength);let s='';for(let i=0;i<b.length;i+=16384)s+=String.fromCharCode(...b.subarray(i,i+16384));return btoa(s)};
const coast=fantasyCoastLines(raster);
const land=Uint8Array.from(raster.water,x=>x!==1?1:0),dist=distanceTo(land,raster.w,raster.h),quant=Uint16Array.from(dist,x=>Math.min(65535,Math.round(x*DIST_Q)));
const coastFixture={sea:coast.sea.map(p=>Array.from(p)),lake:coast.lake.map(p=>Array.from(p)),rings:seaRippleLines(raster,quant,new Uint8Array(raster.w*raster.h).fill(255)).map(ls=>ls.map(p=>Array.from(p))),ice:iceLines(raster,Uint8Array.from(raster.biome,b=>b===2?1:0)).map(l=>({...l,pts:Array.from(l.pts),ink:Array.from(l.ink)}))};
window.result={terrain:document.querySelector('#terrain').toDataURL(),political:document.querySelector('#political').toDataURL(),...extra,
 coastFixture,
 cell:packed(raster.cell),water:packed(raster.water),elev:packed(raster.elev),biome:packed(raster.biome),ice:packed(raster.ice),
 provinces:packed(regionPixels(world,raster,civ)),labels:packed(washFields(p,1).label),
 lines:borderLines(p,1).map(l=>({...l,pts:Array.from(l.pts)})),glyphs:planGlyphs(world).glyphs,forest:packed(planGlyphs(world).forest),
 nations,counts:{cells:world.mesh.n,regions:data.regions.count,cities:data.cities.length,roads:data.roads.length}};
</script>`;
try {
 for(const seed of (process.argv.slice(4).length?process.argv.slice(4).map(Number):[1,7,2024])){
  const page=await browser.newPage({viewport:{width:2048,height:1024}});
  const errors:string[]=[];page.on('pageerror',(e:any)=>errors.push(String(e)));
  await page.route('**/atlas-reference.html',r=>r.fulfill({contentType:'text/html',body:markup}));
  await page.route('**/native-world.json',r=>r.fulfill({contentType:'application/json',path:path.join(out,`world-${seed}.json`)}));
  await page.goto(`http://127.0.0.1:${port}/atlas-reference.html`);
  await page.waitForFunction(()=>!!(window as any).result,null,{timeout:120000});
  const result=await page.evaluate(()=>(window as any).result);
  if(errors.length)throw new Error(errors.join('\n'));
  for(const key of ['terrain','political','habitat','province'])fs.writeFileSync(path.join(out,`${key}-${seed}.png`),Buffer.from(result[key].split(',')[1],'base64'));
  for(const key of ['cell','water','elev','biome','ice','provinces','labels'])fs.writeFileSync(path.join(out,`${key}-${seed}.bin`),Buffer.from(result[key],'base64'));
  fs.writeFileSync(path.join(out,`display-${seed}.json`),JSON.stringify({lines:result.lines,glyphs:result.glyphs,nations:result.nations}));
  fs.writeFileSync(path.join(out,`forest-${seed}.bin`),Buffer.from(result.forest,'base64'));
  fs.writeFileSync(path.join(out,`coasts-${seed}.json`),JSON.stringify(result.coastFixture));
  if(seed===1){
   for(const k of [2,4,8]){
    const png=await page.evaluate(k=>(window as any).zoomImage(k,500,420),k);
    fs.writeFileSync(path.join(out,`political-zoom-${k}-${seed}.png`),Buffer.from(png.split(',')[1],'base64'));
   }
   const png=await page.evaluate(()=>(window as any).zoomImage(4,2048,440));
   fs.writeFileSync(path.join(out,`political-seam-${seed}.png`),Buffer.from(png.split(',')[1],'base64'));
   const polar=await page.evaluate(()=>(window as any).zoomImage(8,880,160));
   fs.writeFileSync(path.join(out,`political-polar-${seed}.png`),Buffer.from(polar.split(',')[1],'base64'));
   for(const k of [1,4]){
    const named=await page.evaluate(k=>(window as any).namedImage(k,k===1?1024:500,k===1?512:420),k);
    fs.writeFileSync(path.join(out,`political-labels-${k}-${seed}.png`),Buffer.from(named.split(',')[1],'base64'));
   }
  }
  console.log('REFERENCE_CAPTURE',seed,result.counts);await page.close();
 }
} finally {await browser.close();await server.close()}
