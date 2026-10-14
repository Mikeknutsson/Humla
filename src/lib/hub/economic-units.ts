export type EconomicMember={kind:string;source_reference:string;object_id:string|null;resolution:string};
export type EconomicPeriod={source_period_id:string|null;valid_from:string;valid_to:string|null;name:string;enabled:boolean;unit_type:string;members:EconomicMember[];main_vehicle:EconomicMember|null};
export type CanonicalEconomicUnit={id:string;version:number;name:string;unit_type:string;enabled:boolean;active_on_date:boolean;business_group:string|null;current_period:EconomicPeriod|null;periods:EconomicPeriod[];components:Array<{source_component_id:string;member:EconomicMember;role:string;allocation_percent:number;valid_from:string|null;valid_to:string|null}>};
export type EconomicUnitCatalog={as_of:string;units:CanonicalEconomicUnit[]};
