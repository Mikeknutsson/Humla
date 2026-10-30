import type {TransportScorecard} from '../kpi/transport-leader';

export type DailyRevenueTarget={days:number;actual:number|null;required:number|null;gap:number|null;reason:string|null};

/** Historical average, using the same authorized revenue, net cost and dated goal as the scorecard. */
export function dailyRevenueTarget(revenue:number|null,cost:number|null,margin:number|null,days:number):DailyRevenueTarget {
 const actual=days>0&&revenue!=null&&Number.isFinite(revenue)?revenue/days:null;
 const reason=days<=0?'Inga vardagar i perioden':cost==null||!Number.isFinite(cost)?'Kostnadsunderlag saknas':margin==null||!Number.isFinite(margin)?'Mål saknas':margin>=100?'Målet måste vara under 100 %':cost<0?'Nettokostnaden är negativ':null;
 const required=reason===null?cost!/(1-margin!/100)/days:null;
 return {days,actual,required,gap:required!=null&&actual!=null?actual-required:null,reason};
}

/** Monday–Friday, inclusive. Includes days without transactions; no inferred operating days. */
export function weekdays(from:string,to:string):number {
 const start=Date.parse(from+'T00:00:00Z'),end=Date.parse(to+'T00:00:00Z');
 if(!Number.isFinite(start)||!Number.isFinite(end)||start>end||end-start>366*86400000)return 0;
 let count=0;for(let d=start;d<=end;d+=86400000){const day=new Date(d).getUTCDay();if(day!==0&&day!==6)count++;}return count;
}

export function unitDailyRevenueTargets(report:TransportScorecard):Record<string,DailyRevenueTarget> {
 const days=weekdays(report.from,report.to);
 return Object.fromEntries(report.units.filter(u=>u.unit_id).map(u=>[u.unit_id!,dailyRevenueTarget(u.revenue,u.cost,u.missing_targets>0?null:u.target_margin_percent,days)]));
}
