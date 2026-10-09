/** Fixed-query original nearestSide/landCover geometry fixture. Development only. */
import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createRequire} from 'node:module';
import {runInNewContext} from 'node:vm';
const root=resolve(process.argv[2]),req=createRequire(resolve(root,'package.json'));
const {transformSync}=createRequire(req.resolve('tsx'))('esbuild');
const source=(await readFile(resolve(root,'src/render/civ/zoomGrid.ts'),'utf8')).replace(/^import .*;\r?\n/gm,'');
const context:any={module:{exports:{}},exports:{},xRange:(p:any)=>{let lo=Infinity,hi=-Infinity;for(let i=0;i<p.length;i+=2){lo=Math.min(lo,p[i]);hi=Math.max(hi,p[i]);}return [lo,hi];}};
runInNewContext(transformSync(source,{loader:'ts',format:'cjs'}).code,context);
const lines=JSON.parse(await readFile('.dbg/atlas-native-reference/display-1.json','utf8')).lines;
const ix=context.module.exports.segIndex(lines,4,[0,0,2048,1024],2048),queries=[];
for(let i=0;i<lines.length;i+=Math.max(1,Math.floor(lines.length/300))) {
 const line=lines[i],p=line.pts,j=Math.floor(p.length/4)*2;
 for(const off of [-3.7,-.1,0,.1,3.7]) {
  const x=p[j]+off,y=p[j+1]+off*.37,cell=context.module.exports.segCell(ix,x,y),side=new Int32Array(1);
  const distance=context.module.exports.nearestSide(ix,cell,x,y,side);
  queries.push({x,y,side:side[0],distance:Number.isFinite(distance)?distance:null});
 }
}
await writeFile('.dbg/atlas-native-reference/zoom-queries-1.json',JSON.stringify(queries));
console.log('ATLAS_ZOOM_REFERENCE',queries.length);
