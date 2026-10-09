/** Development-only numeric fixtures from pinned simplex-noise and upstream util. */
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const root=path.resolve(process.argv[2]);
const {noise3,fbm3,ridged3}=await import(pathToFileURL(path.join(root,'src/gen/util.ts')).href);
const points=[[0,0,0],[.1,.2,.3],[-.1,-.2,-.3],[1,1,1],[1,0,0],[0,1,0],[0,0,1],[-12.7,35.1,-40.5],[100.01,-100.02,12.3]];
const fixture=[1,7,2024,4294967295].map(seed=>{const n=noise3(seed);return {seed,points,noise:points.map(p=>n(...p)),fbm:points.map(p=>fbm3(n,4)(...p)),ridged:points.map(p=>ridged3(n,4)(...p))};});
fs.writeFileSync(process.argv[3],JSON.stringify(fixture));
