'use server';

import {transportDocumentAccess} from '@/lib/hub/transport-document/access';

export async function loadConsignorDetails(name: string) {
  const access = await transportDocumentAccess();
  if (access.status !== 'ready') return {status:'unavailable'} as const;
  if (typeof name !== 'string' || !name.trim() || name.length > 110) return {status:'missing'} as const;

  const key = name.trim();
  const customers = access.db.from('hub_objects')
    .select('name:data->>display_name, organisation:data->>organisation_number, address:data->>postal_address, source:data->>transport_contact_source_url')
    .eq('tenant_id',access.tenantId).eq('object_type','Customer').eq('status','active');

  // Match a company name exactly (apart from case), never infer a link between lookalike names.
  const query = key.includes('*') ? customers.eq('data->>display_name',key) :
    customers.ilike('data->>display_name',key.replace(/[\\%_]/g,'\\$&'));
  const {data,error} = await query.limit(2);
  if (error) return {status:'unavailable'} as const;
  if (data?.length !== 1 || data[0].name?.toLocaleLowerCase('sv') !== key.toLocaleLowerCase('sv')) {
    return {status:'missing'} as const;
  }
  const {organisation,address,source} = data[0];
  if (!organisation && !address) return {status:'missing'} as const;
  return {
    status:'found',
    organisation:organisation?.trim().slice(0,30) ?? '',
    address:address?.trim().slice(0,220) ?? '',
    source:typeof source === 'string' && source.startsWith('https://') ? source : '',
  } as const;
}
