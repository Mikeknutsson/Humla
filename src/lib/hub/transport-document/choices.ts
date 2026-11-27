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

async function objects({db,tenantId}: Access, type: 'Project' | 'Vehicle') {
  const result: HubObject[] = [];
  const batch = 500;
  for (let offset = 0; ; offset += batch) {
    const response = await db.from('hub_objects').select('id,data').eq('tenant_id',tenantId)
      .eq('object_type',type).eq('status','active').order('id').range(offset,offset+batch-1);
    if (response.error) {
      console.error('Transportdokument could not read Hub choices',type,response.error.code);
      return {result,failed:true};
    }
    result.push(...response.data);
    if (response.data.length < batch) return {result,failed:false};
  }
}

export async function readTransportDocumentChoices(access: Access) {
  const [projectData,vehicleData] = await Promise.all([objects(access,'Project'),objects(access,'Vehicle')]);
  const projects = projectData.result.flatMap(({id,data}): HubChoice[] => {
    const value = field(data,'project_number','number','project_reference');
    if (!value) return [];
    const name = field(data,'display_name','project_name','name');
    return [{id,value,label:[value,name && name !== value ? name : ''].filter(Boolean).join(' – ')}];
  }).sort((a,b) => a.label.localeCompare(b.label,'sv',{numeric:true}));
  const vehicles = vehicleData.result.flatMap(({id,data}): HubChoice[] => {
    const value = field(data,'registration_number').replace(/[\s-]/g,'').toUpperCase();
    if (!/^[A-Z]{3}\d{2}[\dA-Z]$/.test(value)) return [];
    const name = field(data,'vehicle_name','name','description');
    return [{id,value,label:[value,name && name !== value ? name : ''].filter(Boolean).join(' – ')}];
  }).sort((a,b) => a.label.localeCompare(b.label,'sv'));
  return {projects,vehicles,failed:projectData.failed || vehicleData.failed};
}
