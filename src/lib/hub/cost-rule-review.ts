import 'server-only';
import type { SupabaseClient } from '@supabase/supabase-js';

export type CostRuleReview = {
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
  if((data??[]).length<500)return result.sort((a,b)=>a.name.localeCompare(b.name,'sv'));
 }
}
