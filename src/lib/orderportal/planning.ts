import type {Order,Resource} from './model';
export const canPlan=(order:Order)=>order.source==='humla'&&['Utkast','Planerad','Pågående'].includes(order.status);
// Shift calendar dates, preserving local clock times even across daylight-saving changes.
export function moveOrderDay(order:Order,anchor:string,target:string):Order{
 const parse=(day:string)=>{if(!/^\d{4}-\d{2}-\d{2}$/.test(day))throw Error('Ogiltigt datum.');const value=Date.parse(day+'T12:00:00Z');if(!Number.isFinite(value)||new Date(value).toISOString().slice(0,10)!==day)throw Error('Ogiltigt datum.');return value;};
 const delta=(parse(target)-parse(anchor))/86400000;
 const shift=(value:string)=>new Date(parse(value.slice(0,10))+delta*86400000).toISOString().slice(0,10)+value.slice(10);
 if(!canPlan(order))throw Error('Ordern kan inte planeras.');
 return {...order,start:shift(order.start),end:shift(order.end)};
}

export function copyOrderForTest(o:Order,resources:Resource[],newId:()=>string=()=>crypto.randomUUID()):Order{return ({...o,id:'',number:'',source:'humla',version:0,status:'Utkast',requestId:newId(),copiedFrom:o.source==='workify'?'Workify '+o.number:o.id,importedAt:'',issues:[],sourceFields:undefined,batches:undefined,projectId:'',project:'',vehicleId:resources.some(r=>r.id===o.vehicleId)?o.vehicleId:'',vehicle:resources.find(r=>r.id===o.vehicleId)?.label||'',driverId:resources.some(r=>r.id===o.driverId)?o.driverId:'',driver:resources.find(r=>r.id===o.driverId)?.label||'',lines:o.lines.map(l=>({...l,id:newId(),sourceId:undefined,fingerprint:undefined,valid:true,errors:[]}))});}

// Maintenance occupies the vehicle schedule, without implying a missing driver.
export function appearsOnResource(order: Pick<Order, 'source'>, kind: string): boolean {
 return kind !== 'driver' || order.source !== 'fordonskontrollen';
}

export function overlapsCalendarDay(order: Pick<Order, 'start' | 'end'>, day: string): boolean {
 if (!order.start || order.start.slice(0, 10) > day) return false;
 if (!order.end || order.end <= order.start) return order.start.slice(0, 10) === day;
 return order.end.slice(0, 10) > day ||
  (order.end.slice(0, 10) === day && !/^T00:00(?::00(?:\.0+)?)?$/.test(order.end.slice(10)));
}
