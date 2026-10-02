create or replace function public.hub_kpi_match_save_many_v1(p_tenant_id uuid,p_items jsonb,p_targets jsonb,p_from date,p_to date,p_reason text)
returns jsonb language plpgsql security invoker set search_path='' as $fn$
declare entry record; response jsonb; saved integer:=0;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if p_targets is null or jsonb_typeof(p_targets)<>'object' then raise exception 'Välj mottagare';end if;
 if (select count(*) from jsonb_each(p_targets)) not between 1 and 7 then raise exception 'Välj en till sju kopplingar';end if;
 for entry in select key,value from jsonb_each_text(p_targets) order by key loop
  response:=public.hub_kpi_match_save_v1(p_tenant_id,p_items,entry.key,entry.value,p_from,p_to,p_reason);
  saved:=saved+(response->>'saved')::integer;
 end loop;
 return jsonb_build_object('saved',saved);
end $fn$;
revoke all on function public.hub_kpi_match_save_many_v1(uuid,jsonb,jsonb,date,date,text) from public,anon;
grant execute on function public.hub_kpi_match_save_many_v1(uuid,jsonb,jsonb,date,date,text) to authenticated;
