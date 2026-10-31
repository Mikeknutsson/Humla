export type DriverReport={status:'ready'|'unlinked';name?:string;from?:string;to?:string;latest_work_date?:string|null;reporting?:'good'|'attention'|'unknown';vehicle_link?:'good'|'partial'|'attention'|'unknown';trend?:'up'|'down'|'steady'|'unknown';days?:{date:string;reporting:'good'|'attention'|'unknown';vehicle:'good'|'attention'|'unknown'}[];weeks?:{from:string;to:string;band:number|null}[];vehicle_economy?:'unknown';fuel?:'unknown'};
export type DriverDirectory={people:{id:string;name:string;linked_user:string|null}[];accounts:{id:string;name:string}[]};
export function driverPeriod(mode:string|undefined,today:string){
 mode=mode??'week';
 const end=new Date(today+'T00:00:00Z');
 if(!['four-weeks','week','month'].includes(mode??'four-weeks'))throw new Error('Ogiltig period');
 let start=new Date(end);
 if(mode==='week')start.setUTCDate(start.getUTCDate()-((start.getUTCDay()+6)%7));
 else if(mode==='month')start.setUTCDate(1);
 else start=new Date(end.getTime()-27*86400000);
 return {from:start.toISOString().slice(0,10),to:today,mode:mode??'four-weeks'};
}
