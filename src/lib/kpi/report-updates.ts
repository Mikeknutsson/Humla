export function kpiReportVersion(status:{generation:string|null;correction_revision?:number}){
 return status.generation?status.generation+':'+String(status.correction_revision??0):null;
}
/** Report refreshes must not discard file selections or unsaved control forms. */
export function canAutoRefreshKpi(pathname:string,query:string){
 if(pathname==='/kpi/fordon')return new URLSearchParams(query).get('tab')!=='tco';
 if(pathname==='/kpi')return ['overview','kpi','internal','monthly','transpa'].includes(new URLSearchParams(query).get('view')??'kpi');
 return ['/kpi/enhet','/kpi/analys','/kpi/mina-enheter','/kpi/transportledare','/kpi/verkstad','/kpi/manadsrapport','/kpi/betalningsprognos','/kpi/korstracka','/kpi/projekt','/kpi/fakturering','/kpi/arbetskostnader','/kpi/reparationskostnader','/kpi/next-kostnader'].includes(pathname);
}
