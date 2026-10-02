import {parseMonthPeriod} from "./period";
// Preserve the actual month selection and drill down from the current scope.
export function analysisHref(query: string, changes: Record<string, string | null> = {}) {
 const p = new URLSearchParams(query);
 p.delete('view'); p.delete('page'); p.delete('auth_retry');
 for (const [key, value] of Object.entries(changes)) {
  if (value === null) p.delete(key); else p.set(key, value);
 }
 if (!('level' in changes)) p.set('level', p.has('project') ? 'transaction' : p.has('unit') || p.has('vehicle') ? 'project' : p.has('group') ? 'unit' : 'group');
 return `/kpi/analys?${p}`;
}
export const filterKeys = ['cost_center','group','unit','vehicle','project','category','kind','source','date_from','date_to'] as const;
export function analysisQuery(params: URLSearchParams) {
 const from=params.get('from') ?? '',to=params.get('to') ?? '';
 if(!/^\d{4}-\d{2}-\d{2}$/.test(from)||!/^\d{4}-\d{2}-\d{2}$/.test(to)||to<from) throw new Error('Välj en giltig rapportperiod.');
 const filters:Record<string,string|number|number[]>=Object.fromEntries(filterKeys.filter(k=>params.has(k)).map(k=>[k,params.get(k)!]));
 if(params.has('months')||params.has('fiscal_year')){const period=parseMonthPeriod(params.get('fiscal_year')??undefined,params.get('months')??undefined);Object.assign(filters,{fiscal_year:period.fiscalYear,selected_months:period.months});}
 const level=params.get('level')??'group',grain=params.get('grain')??'month';
 if(!['cost_center','group','unit','project','transaction'].includes(level)||!['year','month','week','day'].includes(grain)) throw new Error('Ogiltig analysnivå.');
 const page=Number(params.get('page')??0);if(!Number.isInteger(page)||page<0)throw new Error('Ogiltig sida.');
 return {p_from:from,p_to:to,p_filters:filters,p_level:level,p_grain:grain,p_page:page};
}
export type Analysis = {summary:Record<string,number|null>;groups:Array<{key:string;label:string;rows:number;revenue:number;cost:number;result:number}>;periods:Array<{period_start:string;period_end:string;revenue:number;cost:number;result:number}>;transactions:Array<{classification_source?:unknown;cost_center?:string;cost_center_name?:string;fact_id:string;occurred_on:string;kind:string;amount:number;category:string;project:string|null;vehicle:string|null;unit_name:string|null;business_group:string;source:string;description:string|null;account:string|null;file_name:string|null;row_number:number|null;original:unknown}>;export_limit_exceeded:boolean};
