/** Development-only intermediate fixtures for the native environment port. */
import fs from 'node:fs';import path from 'node:path';import {pathToFileURL} from 'node:url';
const root=path.resolve(process.argv[2]),out=path.resolve(process.argv[3]);
const get=(p:string)=>import(pathToFileURL(path.join(root,p)).href);
const {generateWorld,DEFAULT_PARAMS}=await get('src/gen/world.ts');
const {drainage,erode}=await get('src/gen/erosion.ts');
function plain(v:any):any {if(ArrayBuffer.isView(v))return Array.from(v as any);if(Array.isArray(v))return v.map(plain);if(v&&typeof v==='object')return Object.fromEntries(Object.entries(v).map(([k,x])=>[k,plain(x)]));return Number.isFinite(v)||typeof v!=='number'?v:null;}
for(const seed of (process.argv.slice(4).length?process.argv.slice(4).map(Number):[1,7,2024])){
 const world=generateWorld({...DEFAULT_PARAMS,seed});
 const d=drainage(world.mesh,world.tect.land,world.elevation,1e-3);
 fs.writeFileSync(path.join(out,`environment-stages-${seed}.json`),JSON.stringify(plain({tect:world.tect,drainage:d})));
 console.log('ENVIRONMENT_STAGES',seed);
}
