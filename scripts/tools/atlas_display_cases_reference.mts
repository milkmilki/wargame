/** Small, portable original bandLabels edge-case fixtures. Development only. */
import {resolve} from 'node:path';import {pathToFileURL} from 'node:url';import {writeFile} from 'node:fs/promises';
const root=resolve(process.argv[2]);const {bandLabels}=await import(pathToFileURL(resolve(root,'src/render/civ/borders.ts')).href);
const cases=[];
for(const kind of ['junction','small','hole','coast','seam','pole']){
 const w=24,h=16,raw=new Int16Array(w*h),weak=new Uint8Array(w*h),lines:any[]=[];
 for(let y=0;y<h;y++)for(let x=0;x<w;x++) raw[y*w+x]=kind==='junction'?(y>=8?2:x<12?0:1):kind==='seam'?(x<3||x>=21?1:0):kind==='hole'?(x>=9&&x<=14&&y>=5&&y<=10?1:0):kind==='small'?(x===12&&y===8?1:0):kind==='coast'?(y<4?-2:x<12?0:1):(x<12?0:1);
 const add=(p,left,right,closed=false,end0=false,end1=false)=>lines.push({pts:Float32Array.from(p),left,right,closed,end0,end1});
 if(kind==='junction'){add([12,0,12.25,4,12,8],0,1);add([0,8,6,7.8,12,8],2,0);add([12,8,18,8.2,24,8],2,1);}
 else if(kind==='small')add([11.5,7.5,13.5,7.5,13.5,9.5,11.5,9.5,11.5,7.5],1,0,true);
 else if(kind==='hole')add([9,5,14.5,5,15,10.5,9,11,9,5],1,0,true);
 else if(kind==='seam'){add([2.7,0,3.1,8,2.8,16],1,0);add([21.3,0,20.9,8,21.2,16],0,1);}
 else if(kind==='coast'){add([12,4,12.3,6,12,9,12,16],0,1,false,true,false);for(let y=4;y<7;y++)for(let x=8;x<16;x++)weak[y*w+x]=1;}
 else add([12,0,12.4,2,12,8,12,16],0,1,false,true,true);
 const expected=new Int16Array(raw);bandLabels(expected,w,h,1,1,lines,w,weak);
 cases.push({kind,w,h,raw:Array.from(raw),weak:Array.from(weak),lines:lines.map(l=>({...l,pts:Array.from(l.pts)})),expected:Array.from(expected)});
}
await writeFile('tests/fixtures/atlas_native_display_cases.json',JSON.stringify(cases));console.log('ATLAS_DISPLAY_CASES_REFERENCE',cases.length);
