export type KpiUnit = {
 unit_type: 'vehicle' | 'person' | 'overhead' | 'project' | 'compound';
 id: string; name: string; projects: string[]; registrations: string[]; employees: string[];
 valid_from: string; valid_to: string | null; enabled: boolean; revision: number;
};
export type UnitReport = {
 units: Array<{unit_id: string; row_count: number; revenue: number; cost: number; fuel: number; result: number; paid_hours: number; billable_hours: number}>;
 quality: { conflicts?: number; unassigned?: number; invalid?: number; unmapped_accounts?: number };
 conflict_rows: Array<{batch_id: string; row_number: number; project_reference: string; vehicle_registration: string; employee_number: string}>;
};
function values(value: unknown, registration = false) {
 if (typeof value !== 'string' || value.length > 10000) throw new Error('Ogiltig referenslista.');
 const result = [...new Set(value.split(/[\n,;]/).map(v => v.trim().toUpperCase()).filter(Boolean))];
 if (result.some(v => v.length > 100 || (registration && !/^[A-Z]{3}\d{2}[A-Z0-9]$/.test(v)))) throw new Error('Kontrollera referenserna. Regnummer anges utan mellanslag.');
 return result;
}
function date(value: unknown) {
 if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error('Ange ett giltigt datum.');
 const parsed = new Date(value+'T00:00:00Z');
 if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0,10)!==value) throw new Error('Ogiltigt datum.');
 return value;
}
export function unitPayload(body: Record<string, unknown>) {
 const unit_type=body.unit_type;
 if (unit_type !== 'vehicle' && unit_type !== 'person' && unit_type !== 'overhead' && unit_type !== 'compound' && unit_type !== 'project') throw new Error('Välj enhetstyp.');
 let name = typeof body.name === 'string' ? body.name.trim() : '';
 if (!name || name.length > 120) throw new Error('Enhetsnamn krävs, högst 120 tecken.');
 const projects = values(body.projects), registrations=values(body.registrations,true), employees=values(body.employees);
 if (projects.length+registrations.length+employees.length<1 || projects.length+registrations.length+employees.length>300) throw new Error('Ange 1–300 kopplingar.');
 if(unit_type==='project'&&(!projects.length||registrations.length||employees.length))throw new Error('En projekt- eller materialenhet behöver projektkoppling och anges utan fordons- eller personreferenser.');
 const valid_from=date(body.valid_from), valid_to=body.valid_to ? date(body.valid_to) : null;
 if (valid_to && valid_to<valid_from) throw new Error('Slutdatum får inte vara före startdatum.');
 if (typeof body.enabled !== 'boolean') throw new Error('Ogiltig status.');
 const main_vehicle=typeof body.main_vehicle==='string'?body.main_vehicle.trim().toUpperCase():registrations.length===1?registrations[0]:'';
 if(main_vehicle && !registrations.includes(main_vehicle)) throw new Error('Huvudfordonet måste ingå i enheten.');
 if((unit_type==='vehicle'||unit_type==='compound')&&registrations.length){if(!main_vehicle)throw new Error('Välj intäktsbärande huvudfordon.');name=main_vehicle;}
 if(body.business_group_id!==undefined&&body.business_group_id!==null&&typeof body.business_group_id!=='string')throw new Error('Välj en giltig verksamhetsgrupp.');
 const business_group_id=body.business_group_id===undefined?undefined:typeof body.business_group_id==='string'&&body.business_group_id.trim()?body.business_group_id.trim():null;
 if(business_group_id&&!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(business_group_id))throw new Error('Välj en giltig verksamhetsgrupp.');
 if(body.initial_setup!==undefined&&typeof body.initial_setup!=='boolean')throw new Error('Ogiltigt grundkopplingsläge.');
 if(body.finalize_setup!==undefined&&typeof body.finalize_setup!=='boolean')throw new Error('Ogiltig låsning.');
 return {initial_setup:body.initial_setup===true,finalize_setup:body.finalize_setup===true,...(business_group_id!==undefined?{business_group_id}:{}),name,unit_type,projects,registrations,employees,valid_from,valid_to,enabled:body.enabled,...(main_vehicle?{main_vehicle}:{})};
}
