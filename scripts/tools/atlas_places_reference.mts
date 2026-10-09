/** Development-only original geographic-place fixtures; rivers disabled. */
import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const root=resolve(process.argv[2]),out=resolve(process.argv[3]);
const {findPlaces}=await import(pathToFileURL(resolve(root,'src/gen/civ/places.ts')).href);
const {geometryOf}=await import(pathToFileURL(resolve(root,'src/gen/geometry.ts')).href);
for(const seed of [1,7,2024]){
 const data=JSON.parse(await readFile(resolve(out,`world-${seed}.json`),'utf8'));
 const m=data.mesh;m.adjStart=Int32Array.from(m.adj_start);m.x=Float32Array.from(m.x);m.y=Float32Array.from(m.y);m.triangles=Int32Array.from(m.triangles);
 m.sphere={xyz:Float64Array.from(m.xyz),pole: m.n-1};
 const e=data.environment;
 const w={mesh:m,params:data.params,elevation:Float32Array.from(e.elevation),water:Uint8Array.from(e.water),biome:Uint8Array.from(e.biome),temperature:Float32Array.from(e.temperature),seaIce:Float32Array.from(e.seaIce),maxElevation:e.maxElevation,rivers:[]};
 // geometryOf only uses xyz plus existing triangles/adjacency.
 const places=findPlaces(w,data.regions).map(p=>({...p,path:Array.from(p.path)}));
 await writeFile(resolve(out,`places-${seed}.json`),JSON.stringify(places));
 console.log('ATLAS_PLACES_REFERENCE',seed,places.length);
}
