import 'server-only';
import type { SupabaseClient } from '@supabase/supabase-js';

export type AllocationEffect = {rule_id:string;source_rows:number;allocated_rows:number;review_rows:number;allocated_amount:number;review_amount:number;period_from:string|null;period_to:string|null};
export type CostRuleReview = {
 effect?:AllocationEffect;
 id:string;name:string;enabled:boolean;allocation_method:string;valid_from:string|null;valid_to:string|null;
 source_scope:Record<string,unknown>;target_scope:Record<string,unknown>;target_selection_mode:string;
 selected_object_ids:string[];include_in_vehicle_result:boolean;
};

export async function loadCostRules(db:SupabaseClient,tenantId:string):Promise<CostRuleReview[]> {
 const result:CostRuleReview[]=[];
 for(let offset=0;;offset+=500){
  const {data,error}=await db.from('hub_cost_allocation_rules')
   .select('id,name,enabled,allocation_method,valid_from,valid_to,source_scope,target_scope,target_selection_mode,selected_object_ids,include_in_vehicle_result')
   .eq('tenant_id',tenantId).order('id').range(offset,offset+499);
  if(error)throw new Error('Fördelningsreglerna kunde inte hämtas');
  result.push(...(data??[]) as CostRuleReview[]);
  if((data??[]).length<500)break;
 }
 const effects=await db.rpc('hub_cost_allocation_status_v1',{p_tenant:tenantId});
 if(effects.error)throw new Error('Fördelningens ekonomiska effekt kunde inte hämtas');
 const byId=new Map((effects.data as AllocationEffect[]).map(e=>[e.rule_id,e]));
 return result.map(r=>({...r,effect:byId.get(r.id)})).sort((a,b)=>a.name.localeCompare(b.name,'sv'));
}
