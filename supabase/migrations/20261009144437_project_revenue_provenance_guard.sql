-- Project source policy: Workify revenue must have Workify source evidence.
-- Manual revenue imports may carry a legacy Workify label even for NeXT exports.
-- Preserve the existing canonical identity resolution and account 4600 bridge.
do $migration$
declare
 definition text := pg_get_functiondef('private.hub_kpi_project_report_v4(uuid,date,date,text,text,uuid,integer,text,text[])'::regprocedure);
 needle text := '(f.source=''Workify'' and f.kind=''revenue'' and f.cost_center in (''20'',''30'')';
 replacement text := '(f.source=''Workify'' and f.original ?& array[''Ordernummer'',''Artikelnummer'',''Artikeldatum'',''Summa'',''Fakturerad''] and f.kind=''revenue'' and f.cost_center in (''20'',''30'')';
begin
 if length(definition)-length(replace(definition,needle,''))<>length(needle) then
  raise exception 'Expected exactly one project Workify source predicate';
 end if;
 execute replace(definition,needle,replacement);
end $migration$;

-- The project filter and active source generation vary greatly in size.
-- Use a fresh plan and bounded per-operation memory for the expanded history.
alter function private.hub_kpi_project_report_v4(uuid,date,date,text,text,uuid,integer,text,text[]) set plan_cache_mode='force_custom_plan';
alter function private.hub_kpi_project_report_v4(uuid,date,date,text,text,uuid,integer,text,text[]) set work_mem='32MB';
notify pgrst,'reload schema';
