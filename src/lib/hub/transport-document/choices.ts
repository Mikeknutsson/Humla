import 'server-only';
import type {transportDocumentAccess} from './access';
import type {HubChoice} from './fields';

type Access = Extract<Awaited<ReturnType<typeof transportDocumentAccess>>, {status:'ready'}>;
type HubObject = {id: string; data: Record<string,unknown> | null};

function field(data: HubObject['data'], ...keys: string[]) {
  for (const key of keys) {
    const value = data?.[key];
    if (typeof value === 'string' && value.trim()) return value.trim();
    if (typeof value === 'number') return String(value);
  }
  return '';
}

async function truckObjects({db,tenantId}: Access) {
  const result: HubObject[] = [];
  const batch = 500;
  for (let offset = 0; ; offset += batch) {
    const response = await db.from('hub_objects').select('id,data').eq('tenant_id',tenantId)
      .eq('object_type','Vehicle').eq('status','active').eq('data->>vehicle_type','Lastbil').order('id').range(offset,offset+batch-1);
    if (response.error) {
      console.error('Transportdokument could not read trucks',response.error.code);
      return {result,failed:true};
    }
    result.push(...response.data);
    if (response.data.length < batch) return {result,failed:false};
  }
}

async function workifyCustomers({db,tenantId}: Access) {
  const names: string[] = [];
  const batch = 500;
  for (let offset = 0; ; offset += batch) {
    const {data,error} = await db.rpc('hub_ton_price_workify_customers',{p_tenant_id:tenantId})
      .order('name').range(offset,offset+batch-1);
    if (error) {
      console.error('Transportdokument could not read Workify customers',error.code);
      return {names,failed:true};
    }
    const page = (data ?? []) as {name: string}[];
    names.push(...page.map(({name}) => name));
    if (page.length < batch) return {names:names.sort((a,b) => a.localeCompare(b,'sv')),failed:false};
  }
}

export async function readTransportDocumentChoices(access: Access) {
  const [vehicleData,customerData] = await Promise.all([truckObjects(access),workifyCustomers(access)]);
  const vehicles = vehicleData.result.flatMap(({id,data}): HubChoice[] => {
    const value = field(data,'registration_number').replace(/[\s-]/g,'').toUpperCase();
    if (!/^[A-Z]{3}\d{2}[\dA-Z]$/.test(value)) return [];
    const name = field(data,'vehicle_name','name','description');
    return [{id,value,label:[value,name && name !== value ? name : ''].filter(Boolean).join(' – ')}];
  }).sort((a,b) => a.label.localeCompare(b.label,'sv'));
  return {vehicles,customers:customerData.names,customersFailed:customerData.failed,vehiclesFailed:vehicleData.failed};
}
