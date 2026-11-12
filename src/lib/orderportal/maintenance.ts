// @ts-expect-error Node test runner uses the TypeScript source directly.
import {emptyOrder,type Order} from './model.ts';
export type MaintenanceRecord={id:string;version:number;updatedAt:string;vehicleId:string|null;vehicle:string|null;missing:boolean;raw:{id:string|number;number?:string;title?:string;description?:string;start?:string|null;end?:string|null;location?:string;completed_at?:string|null;source?:{title?:string}}};
// API timestamps contain an explicit offset. Never interpret an unzoned source time as UTC.
export function maintenanceTime(value:string|null|undefined):string{
 if(!value||!/(Z|[+-]\d{2}:\d{2})$/.test(value)||!Number.isFinite(Date.parse(value)))return '';
 const parts=new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Stockholm',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(new Date(value));
 const p=Object.fromEntries(parts.map(x=>[x.type,x.value]));return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`;
}
export function maintenanceOrders(records:MaintenanceRecord[]):Order[]{return records.map(r=>{
 const start=maintenanceTime(r.raw.start),end=maintenanceTime(r.raw.end);const issues:string[]=[];
 if(!start)issues.push('Bokad starttid saknas. Visas inte i kalendern.');
 if(!end||end<=start)issues.push('Giltig sluttid saknas. Tillgänglighet efter besöket måste kontrolleras.');
 if(!r.vehicleId)issues.push('Aktiv fordonskoppling saknas i Humla Hub.');
 if(r.missing)issues.push('Saknas i senaste fullständiga källhämtningen. Kontrollera om besöket avbokats.');
 return {...emptyOrder(),id:r.id,number:r.raw.number||String(r.raw.id),source:'fordonskontrollen',title:r.raw.title||'Verkstadsbesök / kontroll',status:r.missing?'Kontrollera källa':r.raw.completed_at?'Utförd':'Planerad',customer:'Internt underhåll · ej debiterbart',vehicleId:r.vehicleId||'',vehicle:r.vehicle||r.raw.source?.title||'',start,end:end>start?end:'',instruction:r.raw.description||'',location:r.raw.location||'',version:r.version,importedAt:r.updatedAt,issues,reference:String(r.raw.id)};
 });}
