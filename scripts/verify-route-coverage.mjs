import fs from 'node:fs';
import path from 'node:path';
const root=process.cwd();
const yaml=fs.readFileSync(path.join(root,'openapi/openapi.yaml'),'utf8').split(/\r?\n/);
const expected=new Set(); let current=null;
for(const line of yaml){let m=line.match(/^  (\/[^:]+):\s*$/);if(m){current=m[1];continue;}m=line.match(/^    (get|post|put|patch|delete):\s*$/i);if(m&&current)expected.add(`${m[1].toUpperCase()} ${current}`);}
const actual=new Set();
for(const dirent of fs.readdirSync(path.join(root,'src/modules'),{withFileTypes:true})){
 if(!dirent.isDirectory())continue;const f=path.join(root,'src/modules',dirent.name,'router.ts');if(!fs.existsSync(f))continue;const text=fs.readFileSync(f,'utf8');const re=/\b[A-Za-z]+Router\.(get|post|put|patch|delete)\(\s*['"]([^'"]+)['"]/g;let m;while((m=re.exec(text))){const p=m[2].replace(/:([A-Za-z0-9_]+)/g,'{$1}');actual.add(`${m[1].toUpperCase()} ${p}`);}
}
// The only intentional extension is a loopback-only, opt-in development helper.
const devOnly=new Set(['POST /dev/payments/{id}/simulate']);
const missing=[...expected].filter(x=>!actual.has(x)).sort();const extra=[...actual].filter(x=>!expected.has(x)&&!devOnly.has(x)).sort();
console.log(`OpenAPI operations: ${expected.size}`);console.log(`Implemented routes: ${actual.size} (including ${[...devOnly].filter(x=>actual.has(x)).length} explicit dev-only route)`);
if(missing.length)console.error('Missing:\n'+missing.join('\n'));if(extra.length)console.error('Extra:\n'+extra.join('\n'));
if(missing.length||extra.length)process.exit(1);console.log('AC-01..AC-12 route coverage: PASS');
