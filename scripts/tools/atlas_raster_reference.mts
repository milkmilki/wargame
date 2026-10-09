/** Development-only source raster intermediates. */
import fs from 'node:fs';import path from 'node:path';import {pathToFileURL} from 'node:url';
const root=path.resolve(process.argv[2]),out=path.resolve(process.argv[3]);
const get=(p:string)=>import(pathToFileURL(path.join(root,p)).href);
const {generateWorld,DEFAULT_PARAMS}=await get('src/gen/world.ts');
const {rasterBase,noiseTiles,rasterize}=await get('src/gen/raster.ts');
const {seaIceNodes}=await get('src/gen/seaice.ts');
for(const seed of (process.argv.slice(4).length?process.argv.slice(4).map(Number):[1,7,2024])){
 const world=generateWorld({...DEFAULT_PARAMS,seed});world.rivers=[];
 const base=rasterBase(world,1),tiles=noiseTiles(seed),raster=rasterize(world,1,false);
 const fields={tri:base.tri,wa:base.wa,wb:base.wb,base:base.elev,planes:base.planes,detail:tiles.dTile,jitter:tiles.jTile,ice_nodes:seaIceNodes(world),temp:raster.temp,precip:raster.precip,ice_conc:raster.iceConc};
 for(const [name,value] of Object.entries(fields))fs.writeFileSync(path.join(out,`${name}-${seed}.bin`),Buffer.from(value.buffer,value.byteOffset,value.byteLength));
 console.log('RASTER_STAGES',seed);
}
