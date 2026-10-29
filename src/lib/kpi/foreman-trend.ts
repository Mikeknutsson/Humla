export type ForemanTrendPoint={
 date:string;revenue:number;cost:number;result:number;margin_percent:number|null;
 target_result:number|null;target_margin_percent:number|null;deviation_amount:number|null;missing_targets:number;
};
export type ForemanTrend={
 from:string;to:string;generation:string;area_target_margin_percent:number|null;points:ForemanTrendPoint[];latest:ForemanTrendPoint|null;
};

const day=86400000;
const time=(date:string)=>Date.parse(date+'T00:00:00Z');
/** Presentation coordinates only; all financial arithmetic is done in Hub. */
export function foremanTrendPlot(trend:ForemanTrend) {
 const showTarget=trend.latest?.target_result!=null;
 const values=[0,...trend.points.map(p=>p.result),...(showTarget?trend.points.flatMap(p=>p.target_result==null?[]:[p.target_result]):[])];
 const low=Math.min(...values),high=Math.max(...values),padding=Math.max((high-low)*0.12,1);
 const min=low-padding,max=high+padding;
 const start=time(trend.from)-day,end=Math.max(time(trend.to),start+day);
 const x=(date:string)=>64+(time(date)-start)/(end-start)*792;
 const y=(amount:number)=>18+(max-amount)/(max-min)*174;
 const origin={x:64,y:y(0)};
 const actual=[origin,...trend.points.map(p=>({x:x(p.date),y:y(p.result)}))];
 const target=showTarget?[origin,...trend.points.filter(p=>p.target_result!=null).map(p=>({x:x(p.date),y:y(p.target_result!)}))]:[];
 const path=(points:{x:number;y:number}[])=>points.map((p,i)=>`${i?'L':'M'}${p.x.toFixed(2)},${p.y.toFixed(2)}`).join(' ');
 return {showTarget,x,y,min,max,zero:y(0),actual:path(actual),target:path(target),
  area:path(actual)+` L${(actual.at(-1)?.x??64).toFixed(2)},${y(0).toFixed(2)} L64,${y(0).toFixed(2)} Z`,
  ticks:[max,(max+min)/2,min]};
}
