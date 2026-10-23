export type TransportMetrics = {
 revenue:number; cost:number; result:number; margin_percent:number|null;
 target_margin_percent:number|null; deviation_amount:number|null; deviation_pp:number|null;
 missing_targets:number; rows:number;
};
export type TransportUnit = TransportMetrics & {unit_id:string|null;unit_name:string|null};
export type TransportGroup = TransportMetrics & {business_group:string};
export type TransportBreakdown = {kind:'revenue'|'cost';category:string;amount:number;rows:number;share_of_revenue:number|null};
export type TransportScorecard={
 from:string;to:string;scope:'transport'|'assigned';generation:string;synced_at:string;
 summary:Omit<TransportMetrics,'revenue'|'cost'|'result'> & {revenue:number|null;cost:number|null;result:number|null;unassigned_rows:number};
 units:TransportUnit[];groups:TransportGroup[];breakdown:TransportBreakdown[];
 sections:{section:string;revenue:number;cost:number;result:number|null;margin_percent:number|null}[];
 transactions:{fact_id:string;occurred_on:string;kind:string;amount:number;category:string;project:string|null;vehicle:string|null;source:string;order_number:string|null;customer:string|null;original:Record<string,unknown>}[];
};
export function validTransportDate(value:string){return /^\d{4}-\d{2}-\d{2}$/.test(value)&&!Number.isNaN(Date.parse(value))&&new Date(value+'T00:00:00Z').toISOString().slice(0,10)===value;}
