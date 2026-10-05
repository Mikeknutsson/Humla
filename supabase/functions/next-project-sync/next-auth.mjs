export async function loadNextToken(sb,tenant,connection,fetchImpl=fetch) {
 const {data:refs,error}=await sb.from('hub_secret_references').select('credential_name,vault_secret_id').eq('tenant_id',tenant).eq('connection_id',connection).eq('status','configured');
 if(error)throw new Error('next_credentials_unavailable');
 const get=async name=>{
  const ref=refs?.find(x=>x.credential_name===name);
  if(!ref?.vault_secret_id)throw new Error('next_missing_'+name);
  const {data,error}=await sb.rpc('hub_internal_vault_secret_v1',{p_secret_id:ref.vault_secret_id});
  if(error||typeof data!=='string'||!data.trim())throw new Error('next_secret_unavailable_'+name);
  return data;
 };
 if(refs?.some(x=>x.credential_name==='access_token'))return get('access_token');
 const form=new URLSearchParams({grant_type:'password',username:await get('database_number'),password:await get('client_key'),scope:'',client_id:await get('client_id'),client_secret:await get('client_secret')});
 let response;
 try {response=await fetchImpl('https://api.next-tech.com/v1/token',{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded',accept:'application/json'},body:form,signal:AbortSignal.timeout(20000)});}catch{throw new Error('next_token_bootstrap_uncertain');}
 if(!response.ok){
  // A simultaneous initial connection may already have saved the one token.
  const {data:r}=await sb.from('hub_secret_references').select('vault_secret_id').eq('tenant_id',tenant).eq('connection_id',connection).eq('credential_name','access_token').eq('status','configured').maybeSingle();
  if(r?.vault_secret_id){const {data,error}=await sb.rpc('hub_internal_vault_secret_v1',{p_secret_id:r.vault_secret_id});if(!error&&typeof data==='string'&&data.trim())return data;}
  throw new Error(response.status===400||response.status===401?'next_new_one_time_key_required':'next_token_http_'+response.status);
 }
 const result=await response.json().catch(()=>null);
 if(typeof result?.access_token!=='string'||!result.access_token.trim())throw new Error('next_token_response_invalid');
 const saved=await sb.rpc('hub_next_store_access_token_v1',{p_tenant_id:tenant,p_connection_id:connection,p_access_token:result.access_token});
 if(saved.error||saved.data?.ok!==true)throw new Error('next_token_storage_failed_new_one_time_key_required');
 return result.access_token;
}

export function nextRowBody(row){
 if(!Number.isSafeInteger(row.next_workorder_id)||row.next_workorder_id<=0)throw new Error('next_workorder_not_verified');
 if(typeof row.next_codeno!=='string'||!row.next_codeno.trim())throw new Error('next_article_not_verified');
 const quantity=Number(row.quantity),price=row.priceunit==null?null:Number(row.priceunit);
 if(!Number.isFinite(quantity)||(price!==null&&!Number.isFinite(price)))throw new Error('next_invalid_quantity_or_price');
 const body={workorderid:row.next_workorder_id,codeno:row.next_codeno,usedquantity:quantity,chargeable:row.chargeable,showinmobile:row.showinmobile};
 if(typeof body.chargeable!=='boolean'||typeof body.showinmobile!=='boolean')throw new Error('next_invalid_row_flags');
 if(row.description)body.text=row.description;
 if(row.unit)body.unit=row.unit;
 if(price!==null)body.priceunit=price;
 return body;
}

export function nextDeliveryStatus(httpStatus,id){
 if(httpStatus>=200&&httpStatus<300)return Number.isSafeInteger(id)&&id>0?'delivered':'needs_review';
 if([401,403,429].includes(httpStatus))return 'retry';
 if([400,404,422].includes(httpStatus))return 'blocked';
 return 'needs_review';
}

export function assertNextTestConnection(connection,commit=false){
 if(!connection||connection.connector_type!=='next_project_api'||connection.configuration?.environment!=='test')throw new Error('next_test_connection_required');
 if(commit&&(connection.configuration.read_only!==false||connection.configuration.outbound_enabled!==true||connection.configuration.write_mode!=='test_only'))throw new Error('next_test_writes_disabled');
}
