/** Development-only reference exporter. Run with the pinned upstream's tsx.
 * Usage: tsx scripts/tools/atlas_reference.mts UPSTREAM OUTPUT [SEED...]
 * Runtime Godot never executes this tool or loads TypeScript.
 */
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = path.resolve(process.argv[2]);
const out = path.resolve(process.argv[3]);
fs.mkdirSync(out, { recursive: true });
// This is a private development checkout. Apply precisely the agreed options.
for (const [file, replacements] of [
  ['src/gen/civ/regions.ts', [['const RIVER_STEPS = 0.9;', 'const RIVER_STEPS = 0;']]],
  ['src/gen/civ/routes.ts', [['const RIVER_ALONG = 1.5;', 'const RIVER_ALONG = 1;'],
    ['const RIVER_CROSS = 0.25;', 'const RIVER_CROSS = 0;']]],
] as const) {
  const target = path.join(root, file);
  let text = fs.readFileSync(target, 'utf8');
  for (const [before, after] of replacements) {
    if (!text.includes(before) && !text.includes(after)) throw new Error(`Upstream mismatch: ${file}`);
    text = text.replace(before, after);
  }
  fs.writeFileSync(target, text);
}
const moduleAt = (name: string) => import(pathToFileURL(path.join(root, name)).href);
const { generateWorld, DEFAULT_PARAMS } = await moduleAt('src/gen/world.ts');
const { computeHabitat } = await moduleAt('src/gen/civ/habitat.ts');
const { buildRegions } = await moduleAt('src/gen/civ/regions.ts');
const { seatCities, buildRoutes } = await moduleAt('src/gen/civ/routes.ts');
const { adjLengths, cellAreas } = await moduleAt('src/gen/civ/geo.ts');
const { geometryOf } = await moduleAt('src/gen/geometry.ts');
const { mulberry32, subSeed, keyed } = await moduleAt('src/gen/util.ts');
const { rasterize } = await moduleAt('src/gen/raster.ts');
const { regionChains, mergeChains } = await moduleAt('src/render/civ/borders.ts');
const { routeLines } = await moduleAt('src/render/civ/routes.ts');
function plain(x: any): any {
  if (ArrayBuffer.isView(x)) return Array.from(x as any);
  if (Array.isArray(x)) return x.map(plain);
  if (x && typeof x === 'object') return Object.fromEntries(Object.entries(x).map(([k,v]) => [k,plain(v)]));
  return x;
}
function ownership(world: any, regions: any, cities: any[]) {
  const geo = geometryOf(world.mesh);
  const count = regions.count;
  const candidates = [...cities.map(c => c.region), ...Array.from({length:count}, (_,i)=>i)];
  const unique = [...new Set<number>(candidates)];
  const seats: number[] = [];
  if (unique.length) seats.push(unique[0]);
  while (seats.length < Math.min(40,count)) {
    let best = -1, score = -1;
    for (const r of unique) {
      if (seats.includes(r)) continue;
      const d = Math.min(...seats.map(s=>geo.dist(regions.seat[r],regions.seat[s])));
      if (d > score) { score = d; best = r; }
    }
    seats.push(best);
  }
  const owners = new Int32Array(count).fill(-1);
  const dist = new Float64Array(count).fill(Infinity);
  const queue: {r:number, d:number, owner:number}[] = [];
  seats.forEach((r,o)=>{ dist[r]=0; owners[r]=o; queue.push({r,d:0,owner:o}); });
  while(queue.length) {
    queue.sort((a,b)=>b.d-a.d || b.owner-a.owner || b.r-a.r);
    const current = queue.pop()!;
    if(current.d !== dist[current.r] || current.owner !== owners[current.r]) continue;
    for(let k=regions.adjStart[current.r]; k<regions.adjStart[current.r+1]; k++) {
      if(regions.adjKind[k] >= 3) continue;
      const next = regions.adj[k], d = current.d + regions.adjLen[k];
      if(d < dist[next]) {dist[next]=d; owners[next]=current.owner; queue.push({r:next,d,owner:current.owner});}
    }
  }
  const components = new Map<number,number[]>();
  for(let r=0;r<count;r++) {
    const l=regions.landmass[r];
    if(!components.has(l)) components.set(l,[]);
    components.get(l)!.push(r);
  }
  for(const rs of components.values()) {
    if(rs.some(r=>owners[r]>=0)) continue;
    let owner=0, best=Infinity;
    for(const r of rs) seats.forEach((s,o)=>{const d=geo.dist(regions.seat[r],regions.seat[s]);if(d<best){best=d;owner=o;}});
    for(const r of rs) owners[r]=owner;
  }
  return { owners, nations:seats.map((r,i)=>({name:`${['岚','苍','澜','景','宁','岳','临','云'][i%8]}${Math.floor(i/8)+1}`,seat:r,hue:(i*0.61803398875)%1})) };
}
const rngReferences = [1,7,2024,0xffffffff].map(seed=>{
  const r=mulberry32(seed);
  return {seed,values_u32:Array.from({length:16},()=>r()*4294967296),sub:subSeed(seed,'mesh'),keyed_u32:keyed(seed,17,4,2)*4294967296};
});
fs.writeFileSync(path.join(out,'rng.json'),JSON.stringify(rngReferences));
if(process.argv.includes('--rng-only')) process.exit(0);
for (const seed of (process.argv.slice(4).length ? process.argv.slice(4).map(Number) : [1,7,2024])) {
  const start=Date.now();
  const world=generateWorld({...DEFAULT_PARAMS,seed});
  const habitat=computeHabitat(world);
  const regions=buildRegions(world,habitat,{regionArea:750});
  const cityList=seatCities(world,habitat,regions).filter(c=>habitat.suitability[c.cell]>1).map(c=>({...c,port:false,region:regions.of[c.cell]}));
  const roads=buildRoutes(world,habitat,regions,{cities:cityList}).filter(r=>r.kind!=='sea');
  const own=ownership(world,regions,cityList);
  const env={...world,suitability:habitat.suitability,capacity:habitat.capacity};
  delete env.mesh; delete env.tect;
  const snapshot={format:'atlas-native-map',version:1,seed,upstream:'103afd3',params:world.params,
    mesh:{...world.mesh,adj_start:world.mesh.adjStart,lengths:adjLengths(world.mesh),areas:cellAreas(world.mesh)},
    environment:env,regions,cities:cityList,roads,ownership:own.owners,nations:own.nations,
    options:{river_usage:'environment_only',city_threshold:1}};
  const civ={regions, routes:roads, settlements:cityList} as any;
  const chains=regionChains(world.mesh,civ);
  const borders=mergeChains(chains,own.owners);
  fs.writeFileSync(path.join(out,`world-${seed}.json`),JSON.stringify(plain(snapshot)));
  fs.writeFileSync(path.join(out,`lines-${seed}.json`),JSON.stringify(plain({chains,borders,roads:routeLines(world.mesh,civ,0)})));
  world.rivers=[];
  const raster=rasterize(world,1,false);
  fs.writeFileSync(path.join(out,`raster-${seed}.json`),JSON.stringify(plain(raster)));
  console.log(`REFERENCE seed=${seed} cells=${world.mesh.n} regions=${regions.count} cities=${cityList.length} roads=${roads.length} ms=${Date.now()-start}`);
}
