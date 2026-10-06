import { DATA_KINDS, type DataKind } from './schema';

export type ReviewRow = {id:string;row_number:number;data_kind:DataKind;source_data:Record<string,unknown>;validation_errors:string[];[key:string]:unknown};
export type ReviewDraft = {row:ReviewRow;values:Record<string,unknown>;reason?:string};
export function workifyOrderNumber(row:ReviewRow) {
 return row.data_kind==='revenue'&&['Artikelnummer','Artikeldatum','Summa','Fakturerad'].every(k=>k in row.source_data)?String(row.source_data.Ordernummer??'').trim():'';
}
export function reviewKey(row:ReviewRow) {const order=workifyOrderNumber(row);return order?`workify:${order}`:row.id;}
export function reviewValues(row:ReviewRow):Record<string,unknown> {
 const values=Object.fromEntries(DATA_KINDS[row.data_kind].fields.map(f=>[f.key,row[f.key]??null]));
 for(const field of ['quantity','available_hours','occupied_hours','paid_hours','billable_hours'])values[field]=row[field]??null;
 if(row.data_kind==='revenue')values.review_target=row.project_reference&&!row.vehicle_registration?'project':row.vehicle_registration?'vehicle':'';
 return values;
}
export function changeReviewRouting(row:ReviewRow,draft:ReviewDraft|undefined,field:string,value:string):ReviewDraft {
 const values={...(draft?.values??reviewValues(row)),[field]:value||null};
 if(row.data_kind==='revenue'&&field==='project_reference'&&value) {values.review_target='project';values.vehicle_registration=null;}
 if(row.data_kind==='revenue'&&field==='vehicle_registration'&&value) {values.review_target='vehicle';values.project_reference=null;}
 return {row:draft?.row??row,values,reason:draft?.reason};
}
export function vehicleSelection(value:unknown) {const text=String(value??'');return ['LASTBIL','INHYRDLASTBIL'].includes(text)?'9009':text;}
export function assignedWorkifyName(row:ReviewRow) {return String(row.source_data.Tilldelad??'').trim()||String(row.source_data.Förare??'').trim()||'–';}
