import type {OverheadKpi} from './overhead';
export type MonthlyMetric={key:string;label:string;value:number|null;unit:'kr'|'%'|'kr/h';status:'source'|'estimate'|'partial'|'missing';basis:string};
export type MonthlyVehicle={key:string;label:string;vehicle:string;invoiced_revenue:number;recorded_revenue:number;cost:number;fuel:number;hired:boolean};
export type FuelSourceReport={total_cost:number|null;piusi_cost:number|null;piusi_liters:number|null;next_cost:number|null;next_tank_purchase_excluded:number;piusi_rows:number;review_rows:number;provisional_rows:number;unclassified_rows:number;last_transaction_at:string|null;source_state:{captured_at:string;last_connector_success:string|null;connector_status:string|null};basis:string;transactions:Array<{source:string;id:string;dt:string;vehicle:string|null;amount:number|null;liters:number|null;price_status:string;product:string|null}>};
export type TranspaPeriodTime={worked_hours?:number|null;reported_vehicle_hours:number|null;available_vehicle_hours:number|null;worked_driver_hours:number|null;revenue_linked_driver_hours:number|null;unclassified_driver_hours:number|null;vehicles:Array<Record<string,string|number>>;drivers:Array<Record<string,string|number>>};
export type MonthlyCostUnit={utilization?:number|null;cost_per_hour?:number|null;revenue_per_hour?:number|null;next_project_hours?:number|null;next_workshop_hours?:number|null;key:string;label:string;revenue:number;cost:number;fuel:number;fuel_liters:number|null;worked_hours:number|null;occupied_hours:number|null;available_hours:number|null;children:Array<{vehicle?:string|null;project?:string|null}>};
export type NextTimePeriod={available:boolean;project_hours:number|null;workshop_hours:number|null;absence_hours:number;supplement_hours:number;review_rows:number;unmapped_unit_hours:number;workshop_hours_without_cost_reference:number;workshop_estimated_repair_cost?:number;basis:string;workshop_cost_references:Array<{project:string;project_id:string|null;month_start:string;hours:number;posted_repair_debit:number|null;estimated_repair_cost?:number|null;cost_rows:number}>};
export type PersonnelComparison={calculated_cost?:number|null;transpa_estimate?:number|null;next_personnel_cost?:number|null;provisional_work_cost?:number|null;other_personnel_cost?:number|null;booked_cost?:number|null;cost_difference?:number|null;result_effect?:number|null;overhead_allocation?:number|null;management_allocation?:number|null;next_management_cost?:number|null;basis?:string};
export type AccountingBasis={personnel_comparison?:PersonnelComparison;stena_rule?:string;stena_timing?:Array<{delivery_month:string;rows:number;amount:number;actual_invoice_date_rows:number;invoice_date_assumed:string;payment_date_assumed:string}>;fortnox_verified:boolean;status:string;revenue_basis:string;cost_basis:string;next_cost_in_report:number|null;cost_before_report_adjustments:number|null;report_cost_adjustment:number|null;unallocated_cost:number|null;fortnox_revenue?:number|null;fortnox_cost?:number|null;fortnox_result?:number|null;difference?:number|null;revenue_difference?:number|null;cost_difference?:number|null;reference_file?:string|null;reference_notes?:string|null;reference_metrics?:Record<string,{value:number;previous:number|null;row:number}>;sources:Array<{source:string;kind:string;rows:number;amount:number}>};
export type TransportPeriodReport={accounting_basis?:AccountingBasis;next_time?:NextTimePeriod;internal_revenue?:number|null;internal_revenue_basis?:string;workshop_repair_debit?:number|null;overhead?:OverheadKpi;economic_units?:MonthlyCostUnit[];fuel_sources?:FuelSourceReport;time?:TranspaPeriodTime;metrics:MonthlyMetric[];recorded_revenue:number|null;uninvoiced_revenue:number|null;cost:number|null;estimated_payroll:number|null;fuel:number|null;fuel_share:number|null;active_vehicle_count:number;coverage:{requested_months:number[];revenue_months:number;cost_months:number};vehicles:MonthlyVehicle[]};
export type MonthlyTransportReport={version:1;previous?:{period:MonthlyTransportReport['period'];month:TransportPeriodReport;ytd:TransportPeriodReport}|null;previous_available?:boolean;excluded_projects?:Array<{project_id:string;name:string}>;reconciliation?:{status:string;workify_in_kpi:number;reported_workify:number;difference:number;reference:string;basis:string};correction_revision?:number;title:string;tenant:string;period:{fiscal_year:number;month:number;months?:number[];from:string;to:string;ytd_from:string;ytd_months:number[]};scope:Record<string,string>;cost_centers?:{code:string;name:string}[];month:TransportPeriodReport;ytd:TransportPeriodReport;indicators:{reported_vehicle_utilization:number|null;reported_hours:number|null;available_hours:number|null;definition:string};generation:string;synced_at:string;generated_at:string;source_document:string;invoicing_rule:string};
export const metricStatus={source:'Enligt underlag och rapportregel',estimate:'Preliminärt / uppskattning',partial:'Ofullständigt periodunderlag',missing:'Underlag saknas'};
export function monthlyValue(value:number|null|undefined,unit:string){return value==null?'Underlag saknas':new Intl.NumberFormat('sv-SE',{maximumFractionDigits:unit==='%'?1:0}).format(value)+' '+unit;}
export function monthlyReportMetrics(report:MonthlyTransportReport){const metrics=report.month.metrics.filter(m=>! /^(overhead|management)(_|$)/.test(m.key));const internal=metrics.find(m=>m.key==='internal_revenue');return metrics.filter(m=>m.key!=='internal_revenue').flatMap(m=>m.key==='revenue'&&internal?[m,internal]:[m]);}
export function monthlyRows(report:MonthlyTransportReport){return monthlyReportMetrics(report).map((metric)=>({Nyckeltal:metric.label,Månad:metric.value,YTD:report.ytd.metrics.find(m=>m.key===metric.key)?.value??null,'Månad fg. år':report.previous?.month.metrics.find(m=>m.key===metric.key)?.value??null,'YTD fg. år':report.previous?.ytd.metrics.find(m=>m.key===metric.key)?.value??null,Enhet:metric.unit,Status:metricStatus[metric.status],'Status YTD':metricStatus[report.ytd.metrics.find(m=>m.key===metric.key)?.status??'missing'],Definition:metric.basis}));}

export type MonthlyComparisonRow={label:string;unit:string;values:Array<number|null|undefined>};
export type MonthlyComparisonSection={key:string;title:string;note?:string;rows:MonthlyComparisonRow[]};
export function monthlyComparisonSections(report:MonthlyTransportReport):MonthlyComparisonSection[]{
 const periods=[report.month,report.ytd,report.previous?.month,report.previous?.ytd];
 const metrics:MonthlyComparisonRow[]=monthlyReportMetrics(report).map(m=>({label:m.label,unit:m.unit,values:periods.map(p=>{const v=p?.metrics.find(x=>x.key===m.key);return v?.status==='missing'?null:v?.value;})}));
 const overview=(key:keyof TransportPeriodReport,label:string,unit:string):MonthlyComparisonRow=>({label,unit,values:periods.map(p=>p?.[key] as number|null|undefined)});
 const accounting:MonthlyComparisonRow[]=[
 {label:'Bokföringsrapport – intäkter',unit:'kr',values:periods.map(p=>p?.accounting_basis?.fortnox_revenue)},
 {label:'Bokföringsrapport – resultat (slutrad Total)',unit:'kr',values:periods.map(p=>p?.accounting_basis?.fortnox_result)},
 {label:'Intäktsdifferens: Humla minus bokföringsrapport',unit:'kr',values:periods.map(p=>p?.accounting_basis?.revenue_difference)},
 {label:'Resultatdifferens: Humla minus bokföringsrapport',unit:'kr',values:periods.map(p=>p?.accounting_basis?.difference)},
 ...(['fuel','personnel','depreciation'] as const).map(key=>({label:({fuel:'Bränsle',personnel:'Personal',depreciation:'Avskrivningar'}[key])+' enligt bokföringsrapport',unit:'kr',values:periods.map(p=>{const value=p?.accounting_basis?.reference_metrics?.[key]?.value;return value==null?null:-value;})})),
 {label:'NeXT-kostnader i Humlas rapportunderlag',unit:'kr',values:periods.map(p=>p?.accounting_basis?.next_cost_in_report)},
 {label:'Rapportjusteringar efter grundunderlaget',unit:'kr',values:periods.map(p=>p?.accounting_basis?.report_cost_adjustment)},
 {label:'Varav kostnader utan enhetsfördelning',unit:'kr',values:periods.map(p=>p?.accounting_basis?.unallocated_cost)}];
 return [{key:'accounting',title:'Avstämning mot bokföring',rows:accounting},{key:'personnel',title:'Personal – beräknat och bokfört',note:report.month.accounting_basis?.personnel_comparison?.basis,rows:([
 ['calculated_cost','Personalkostnad i Humlas modell'],
 ['transpa_estimate','Varav TransPA – beräknad lön och PO'],
 ['next_personnel_cost','Varav NEXT – importerad personalkostnad'],
 ['provisional_work_cost','Varav preliminär arbetskostnad'],
 ['other_personnel_cost','Varav övrig personal i modellen'],
 ['booked_cost','Bokförd personalkostnad – uppladdat underlag'],
 ['cost_difference','Personalkostnad: Humla minus bokfört'],
 ['result_effect','Resultateffekt av skillnaden i personalkostnad'],
 ['overhead_allocation','Separat: fördelad overhead'],
 ['management_allocation','Separat: fördelad arbetsledning'],
 ['next_management_cost','Separat: NEXT – arbetsledningskostnad']
 ]as const).map(([key,label])=>({label,unit:'kr',values:periods.map(p=>p?.accounting_basis?.personnel_comparison?.[key])}))},{key:'metrics',title:'Nyckeltal',rows:metrics},
 {key:'economy',title:'Ekonomiskt underlag',rows:[overview('recorded_revenue','Registrerade intäkter','kr'),overview('cost','Totala kostnader','kr'),overview('workshop_repair_debit','Varav intern verkstadsdebitering – Rep','kr'),{label:'Varav preliminär verkstadskostnad – Rep',unit:'kr',values:periods.map(p=>p?.next_time?.workshop_estimated_repair_cost)},overview('estimated_payroll','Personalkostnad – schablon','kr'),overview('active_vehicle_count','Aktiva egna fordonsenheter','st')]},
 {key:'fuel',title:'Bränsle – Piusi + NEXT',rows:[overview('fuel','Bränsle totalt','kr'),overview('fuel_share','Bränsle / omsättning','%'),...([
 ['piusi_cost','Piusi tankningar','kr'],['piusi_liters','Piusi tankad mängd','liter'],['next_cost','Övrigt bränsle i NEXT','kr'],['next_tank_purchase_excluded','NEXT egen tank, avstämning utanför summan','kr'],['piusi_rows','Tankningar i urvalet','st'],['provisional_rows','Preliminära priser','st'],['review_rows','Prisrader för granskning','st']
 ]as const).map(([key,label,unit])=>({label,unit,values:periods.map(p=>p?.fuel_sources?.[key])}))]},
 {key:'time',title:'Timmar',rows:([
 ['worked_hours','Arbetad tid'],['reported_vehicle_hours','Arbetad fordonstid'],['available_vehicle_hours','Tillgänglig fordonskapacitet – fordon med timmar'],['revenue_linked_driver_hours','Intäktskopplad tid'],['unclassified_driver_hours','Oklassificerad tid']
 ]as const).map<MonthlyComparisonRow>(([key,label])=>({label,unit:'h',values:periods.map(p=>p?.time?.[key])})).concat([
 {label:'Verkstadstid – NEXT (Rep)',unit:'h',values:periods.map(p=>p?.next_time?.workshop_hours)}])}];
}
export function monthlyUnitComparisons(report:MonthlyTransportReport){
 const periods=[report.month,report.ytd,report.previous?.month,report.previous?.ytd];
 const units=new Map(periods.slice().reverse().flatMap(p=>(p?.economic_units??[]).map(u=>[u.key,u]as const)));
 return [...units.values()].sort((a,b)=>a.label.localeCompare(b.label,'sv')).map(u=>({key:u.key,label:u.label,rows:([
 ['revenue','Omsättning','kr'],['cost','Kostnad','kr'],['fuel','Bränsle','kr'],['worked_hours','Arbetad tid','h'],['next_workshop_hours','Verkstadstid – NEXT (Rep)','h'],['occupied_hours','Arbetad fordonstid','h'],['utilization','Beläggningsgrad','%'],['cost_per_hour','Kostnad / arbetad timme','kr/h'],['revenue_per_hour','Intäkt / arbetad timme','kr/h']
 ]as const).map(([key,label,unit])=>({label,unit,values:periods.map(p=>p?.economic_units?.find(x=>x.key===u.key)?.[key])}))}));
}
