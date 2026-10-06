import {parseMonthPeriod,monthPeriodQuery} from './period';

export const selectionKeys=['fiscal_year','months','from','to','cost_center','group','unit','vehicle','project','category','kind','source','date_from','date_to'] as const;

export function selectionCookie(userId:string){return `humla_kpi_selection_v1_${userId}`;}

export function readSavedSelection(value:string|undefined):URLSearchParams|null {
 if(!value||value.length>2500)return null;
 try{
  const saved=JSON.parse(value);
  if(saved?.version!==1||typeof saved.query!=='string'||saved.query.length>2000)return null;
  const params=new URLSearchParams(saved.query);
  if([...params.keys()].some(k=>!selectionKeys.includes(k as typeof selectionKeys[number])))return null;
  if(params.has('fiscal_year')||params.has('months'))parseMonthPeriod(params.get('fiscal_year')??undefined,params.get('months')??undefined);
  for(const key of ['from','to','date_from','date_to'])if(params.has(key)&&!/^\d{4}-\d{2}-\d{2}$/.test(params.get(key)!))return null;
  return params;
 }catch{return null;}
}

export function selectionFromQuery(params:URLSearchParams){
 const scope=new URLSearchParams();
 for(const key of selectionKeys){const value=params.get(key);if(value)scope.set(key,value);}
 return scope;
}

export function defaultSelection(now=new Date()){
 return new URLSearchParams(monthPeriodQuery(parseMonthPeriod(undefined,undefined,now)));
}

// A URL with an explicit period is authoritative, including removed filters.
// A section-only link inherits the selection without overwriting local options.
export function restoreSelection(params:URLSearchParams,saved:URLSearchParams|null){
 if(params.get('view')==='internal') {
  if(!saved||params.has('cost_center')||!saved.has('cost_center'))return null;
  const result=new URLSearchParams(params);result.set('cost_center',saved.get('cost_center')!);return result.toString();
 }
 if(!saved||['fiscal_year','months','from','to'].some(k=>params.has(k)))return null;
 const result=new URLSearchParams(params);
 for(const [key,value] of saved)if(!result.has(key))result.set(key,value);
 return result.toString()===params.toString()?null:result;
}
