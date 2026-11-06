export type MaterialSale={material_key:string|null;material_name:string|null;quantity:number|string|null;unit:string|null;sale_amount:number|string|null;occurred_on:string};
export type MaterialPrice={material_key:string;purchase_price_per_unit:number|string|null;unit:string;valid_from:string;valid_to:string|null};
export type MaterialRow={material_key:string;material_name:string;unit:string;sold_quantity:number;sale_amount:number;purchase_price_per_unit:number|null;estimated_purchase_cost:number|null;gross_result:number|null;margin_pct:number|null;missing_price_rows:number};
export function materialReconciliation(sales:MaterialSale[],prices:MaterialPrice[],months?:number[]){
 const rows=new Map<string,MaterialRow>();
 for(const sale of sales){
  if(months&&!months.includes(Number(sale.occurred_on.slice(5,7))))continue;
  const key=String(sale.material_key??'');
  if(sale.unit!=='ton'||!/^S(?!T)/i.test(key)||/inkl?\.?\s*transport|ink\s*transport/i.test(sale.material_name??''))continue;
  const candidates=prices.filter(p=>p.material_key===key&&p.unit==='ton'&&p.valid_from<=sale.occurred_on&&(!p.valid_to||p.valid_to>=sale.occurred_on)).sort((a,b)=>b.valid_from.localeCompare(a.valid_from));
  const price=candidates[0]?.purchase_price_per_unit==null?null:Number(candidates[0].purchase_price_per_unit);
  const quantity=sale.quantity==null?null:Number(sale.quantity);
  const r=rows.get(key)??{material_key:key,material_name:sale.material_name??key,unit:'ton',sold_quantity:0,sale_amount:0,purchase_price_per_unit:null,estimated_purchase_cost:0,gross_result:null,margin_pct:null,missing_price_rows:0};
  r.sold_quantity+=quantity!=null&&Number.isFinite(quantity)?quantity:0;r.sale_amount+=Number(sale.sale_amount??0);
  if(price==null||!Number.isFinite(price)||quantity==null||!Number.isFinite(quantity)){r.missing_price_rows++;r.estimated_purchase_cost=null;}
  else if(r.estimated_purchase_cost!=null)r.estimated_purchase_cost+=Math.round(price*quantity*100)/100;
  rows.set(key,r);
 }
 for(const r of rows.values())if(r.estimated_purchase_cost!=null){
  r.estimated_purchase_cost=Math.round(r.estimated_purchase_cost*100)/100;
  r.purchase_price_per_unit=r.sold_quantity?r.estimated_purchase_cost/r.sold_quantity:null;
  r.gross_result=r.sale_amount-r.estimated_purchase_cost;r.margin_pct=r.sale_amount?r.gross_result/r.sale_amount*100:null;
 }
 return [...rows.values()].sort((a,b)=>b.sale_amount-a.sale_amount);
}
