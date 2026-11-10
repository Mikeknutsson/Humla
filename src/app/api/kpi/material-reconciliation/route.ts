import {createClient} from '@/lib/supabase/server';
import {analysisQuery} from '@/lib/kpi/analysis';
import {materialReconciliation,type MaterialSale} from '@/lib/hub/material-reconciliation';

export async function GET(request:Request){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();
 if(!user)return Response.json({error:'Inloggning krävs'},{status:401});
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(!member)return Response.json({error:'Arbetsyta saknas'},{status:403});
 const {data:canRead}=await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.read'});
 if(!canRead)return Response.json({error:'Åtkomst saknas'},{status:403});
 let scope:ReturnType<typeof analysisQuery>;
 try{scope=analysisQuery(new URL(request.url).searchParams);}catch{return Response.json({error:'Ogiltig period'},{status:400});}
 const from=String(scope.p_filters.date_from??scope.p_from),to=String(scope.p_filters.date_to??scope.p_to);
 const sales:MaterialSale[]=[];
 for(let offset=0;;offset+=1000){
  const {data,error}=await db.from('hub_workify_material_sales_v1').select('transaction_id,material_key,material_name,quantity,unit,sale_amount,occurred_on').eq('tenant_id',member.tenant_id).gte('occurred_on',from).lte('occurred_on',to).eq('unit','ton').order('transaction_id').range(offset,offset+999);
  if(error)return Response.json({error:'Materialförsäljningen kunde inte hämtas'},{status:503});
  sales.push(...data as MaterialSale[]);if(data.length<1000)break;
 }
 const keys=[...new Set(sales.map(r=>r.material_key).filter((key):key is string=>Boolean(key)))];
 const {data:prices,error:priceError}=keys.length?await db.from('hub_material_purchase_prices').select('material_key,purchase_price_per_unit,unit,valid_from,valid_to').eq('tenant_id',member.tenant_id).in('material_key',keys):{data:[],error:null};
 if(priceError)return Response.json({error:'Inköpspriserna kunde inte verifieras'},{status:503});
 const months=Array.isArray(scope.p_filters.selected_months)?scope.p_filters.selected_months:undefined;
 return Response.json({rows:materialReconciliation(sales,prices??[],months),months:months??null},{headers:{'Cache-Control':'private, no-store'}});
}
