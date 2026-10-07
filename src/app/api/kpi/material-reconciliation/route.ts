import {createClient} from '@/lib/supabase/server';

export async function GET(request:Request){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();
 if(!user)return Response.json({error:'Inloggning krävs'},{status:401});
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').maybeSingle();
 if(!member)return Response.json({error:'Arbetsyta saknas'},{status:403});
 const {data:canRead}=await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.read'});
 if(!canRead)return Response.json({error:'Åtkomst saknas'},{status:403});
 const q=new URL(request.url).searchParams,from=q.get('from'),to=q.get('to');
 if(!/^\d{4}-\d{2}-\d{2}$/.test(from??'')||!/^\d{4}-\d{2}-\d{2}$/.test(to??''))return Response.json({error:'Ogiltig period'},{status:400});
 const {data:sales,error}=await db.from('hub_workify_material_sales_v1').select('material_key,material_name,quantity,unit,sale_amount,occurred_on').eq('tenant_id',member.tenant_id).gte('occurred_on',from!).lte('occurred_on',to!).eq('unit','ton');
 if(error)return Response.json({error:'Materialförsäljningen kunde inte hämtas'},{status:400});
 const pure=(sales??[]).filter(r=>/^S(?!T)/i.test(String(r.material_key??''))&&!/inkl?\s*transport|ink\s*transport/i.test(String(r.material_name??'')));
 const keys=[...new Set(pure.map(r=>r.material_key).filter(Boolean))];
 const {data:prices}=keys.length?await db.from('hub_material_purchase_prices').select('material_key,purchase_price_per_unit,unit,valid_from,valid_to').eq('tenant_id',member.tenant_id).in('material_key',keys):{data:[]};
 const rows=new Map<string,{material_key:string;material_name:string;unit:string;sold_quantity:number;sale_amount:number;purchase_price_per_unit:number|null;estimated_purchase_cost:number|null;gross_result:number|null;margin_pct:number|null}>();
 for(const sale of pure){const key=String(sale.material_key),date=String(sale.occurred_on);const candidates=(prices??[]).filter(p=>p.material_key===key&&p.unit==='ton'&&p.valid_from<=date&&(!p.valid_to||p.valid_to>=date)).sort((a,b)=>String(b.valid_from).localeCompare(String(a.valid_from)));const price=candidates[0]?.purchase_price_per_unit==null?null:Number(candidates[0].purchase_price_per_unit);const r=rows.get(key)??{material_key:key,material_name:String(sale.material_name??key),unit:'ton',sold_quantity:0,sale_amount:0,purchase_price_per_unit:price,estimated_purchase_cost:null,gross_result:null,margin_pct:null};r.sold_quantity+=Number(sale.quantity??0);r.sale_amount+=Number(sale.sale_amount??0);if(r.purchase_price_per_unit==null)r.purchase_price_per_unit=price;rows.set(key,r);}
 for(const r of rows.values()){if(r.purchase_price_per_unit!=null){r.estimated_purchase_cost=r.sold_quantity*r.purchase_price_per_unit;r.gross_result=r.sale_amount-r.estimated_purchase_cost;r.margin_pct=r.sale_amount?r.gross_result/r.sale_amount*100:null;}}
 return Response.json({rows:[...rows.values()].sort((a,b)=>b.sale_amount-a.sale_amount)});
}
