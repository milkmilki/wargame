/** Development-only extraction of upstream grammar data and independent name fixtures. */
import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {runInNewContext} from 'node:vm';
const root=resolve(process.argv[2]);
const req=createRequire(resolve(root,'package.json')); const {transformSync}=createRequire(req.resolve('tsx'))('esbuild');
const source=await readFile(resolve(root,'src/gen/names/eastern.ts'),'utf8');
const grammar=source.slice(source.indexOf('const C_HAO'),source.indexOf('export function easternCandidate'));
const preamble=`
const pair=(a,b)=>({op:'pair',a,b});
const combos=(spec)=>({op:'combos',spec});
const named=(core,generics)=>({op:'named',core,generics});
const prefixed=(prefixes,core,suffix='')=>({op:'prefixed',prefixes,core,suffix});
const oneOf=(chars)=>({op:'one',chars});
const either=(...items)=>({op:'either',items});
const W=(...items)=>items;
`;
const context:any={module:{exports:{}},exports:{}};
runInNewContext(transformSync(preamble+grammar,{loader:'ts',format:'cjs'}).code,context);
const tone=(key:string)=>[...source.matchAll(new RegExp(`const ${key} =([\\s\\S]*?);`,'g'))][0][1].match(/'[^']*'/g)!.map(s=>s.slice(1,-1)).join('');
const {BLOCKLIST_FOR_TEST}=await import(pathToFileURL(resolve(root,'src/gen/names/filters.ts')).href);
await writeFile('assets/atlas/eastern-names.json',JSON.stringify({source:'civ-atlas 103afd3, AGPL-3.0-only',styles:context.module.exports.EASTERN_STYLES,ping:tone('PING'),ze:tone('ZE'),blocked:{chars:[...BLOCKLIST_FOR_TEST.chars],substr:BLOCKLIST_FOR_TEST.substr,exact:[...BLOCKLIST_FOR_TEST.exact]}},null,2));
const {createNamer,NAME_KINDS}=await import(pathToFileURL(resolve(root,'src/gen/names/index.ts')).href);
const {WESTERN_STYLES}=await import(pathToFileURL(resolve(root,'src/gen/names/western.ts')).href);
const trSource=await readFile(resolve(root,'src/gen/names/transcribe.ts'),'utf8');
const filterSource=await readFile(resolve(root,'src/gen/names/filters.ts'),'utf8');
const trCtx:any={};
runInNewContext(transformSync(trSource.replace(/export /g,'')+'\nglobalThis.tables={cols:COLS,rows:BASE_ROWS,lone:BASE_LONE,diph:DIPH};',{loader:'ts'}).code,trCtx);
const filterCtx:any={TextDecoder,Uint8Array,atob};
runInNewContext(transformSync(filterSource.replace(/export /g,'')+'\nglobalThis.latin={exact:[...BLOCKED_LATIN_EXACT],substr:BLOCKED_LATIN_SUBSTR};',{loader:'ts'}).code,filterCtx);
await writeFile('assets/atlas/western-names.json',JSON.stringify({source:'civ-atlas 103afd3, AGPL-3.0-only',styles:WESTERN_STYLES,transcription:trCtx.tables,blocked:filterCtx.latin},null,2));
const fixtures=[];
for(const seed of [1,7,2024]) for(const style of [...WESTERN_STYLES.map(s=>s.id),'central','xianxia','frontier','mythic']) {
 const n=createNamer(seed,style),sequential=[];
 for(let t=0;t<120;t++){const kind=NAME_KINDS[t%6];sequential.push({kind,value:n.name(kind)});}
 const keyed=[];
 for(const kind of NAME_KINDS){const stream=n.keyed(kind,12,89);for(let t=0;t<60;t++) keyed.push({kind,value:stream()});}
 fixtures.push({seed,style,sequential,keyed});
}
await writeFile('tests/fixtures/atlas_native_names.json',JSON.stringify(fixtures));
console.log('ATLAS_NAMES_REFERENCE',fixtures.length);
