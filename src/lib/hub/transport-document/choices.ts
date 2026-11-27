import 'server-only';
import type {transportDocumentAccess} from './access';
import type {HubChoice} from './fields';

type Access = Extract<Awaited<ReturnType<typeof transportDocumentAccess>>, {status:'ready'}>;
type Truck = {id: string; registration: string | null; name: string | null};

async function truckObjects({db,tenantId}: Access) {
  const result: Truck[] = [];
  const batch = 500;
  for (let offset = 0; ; offset += batch) {
    const response = await db.rpc('hub_transport_document_trucks',{p_tenant:tenantId})
      .order('id').range(offset,offset+batch-1);
    if (response.error) {
      console.error('Transportdokument could not read trucks',response.error.code);
      return {result,failed:true};
    }
    const page = (response.data ?? []) as Truck[];
    result.push(...page);
    if (page.length < batch) return {result,failed:false};
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
  const vehicles = vehicleData.result.flatMap(({id,registration,name}): HubChoice[] => {
    const value = (registration ?? '').replace(/[\s-]/g,'').toUpperCase();
    if (!/^[A-Z]{3}\d{2}[\dA-Z]$/.test(value)) return [];
    return [{id,value,label:[value,name && name !== value ? name : ''].filter(Boolean).join(' – ')}];
  }).sort((a,b) => a.label.localeCompare(b.label,'sv'));
  return {vehicles,customers:customerData.names,customersFailed:customerData.failed,vehiclesFailed:vehicleData.failed};
}
