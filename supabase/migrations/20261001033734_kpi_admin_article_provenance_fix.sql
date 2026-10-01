create or replace function public.hub_kpi_save_rule_v1(p_tenant_id uuid,p_kind text,p_rule jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare effective date; ending date; reference text; cat text; result uuid; reg text;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI administrator required';end if;
 effective:=(p_rule->>'valid_from')::date;ending:=nullif(p_rule->>'valid_to','')::date;reference:=trim(p_rule->>'reference');cat:=p_rule->>'category';reg:=upper(trim(p_rule->>'vehicle'));
 if effective is null or nullif(reference,'') is null or length(reference)>100 or (ending is not null and ending<effective) then raise exception 'Invalid reference/date';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||p_kind||reference,0));
 if p_kind='project_group' then return public.hub_kpi_set_project_group_v2(p_tenant_id,reference,(p_rule->>'group_id')::uuid,effective);
 elsif p_kind='cost' then
  if reference !~ '^[0-9]{1,8}$' or cat not in ('personnel','fuel','service_repair','depreciation','fixed','other','material','tipp_deponi','hired') then raise exception 'Invalid account/category';end if;
  if exists(select 1 from public.kpi_cost_category_rules where tenant_id=p_tenant_id and account=reference and valid_from>=effective) then raise exception 'Start date must follow existing history';end if;
  update public.kpi_cost_category_rules set valid_to=effective-1 where tenant_id=p_tenant_id and account=reference and (valid_to is null or valid_to>=effective);
  insert into public.kpi_cost_category_rules(tenant_id,account,cost_category,valid_from,valid_to,source,include_in_vehicle_result) values(p_tenant_id,reference,cat,effective,ending,'kpi_admin_dated',coalesce((p_rule->>'include_in_vehicle_result')::boolean,true)) returning id into result;
 elsif p_kind='article' then
  if p_rule->>'target_type' not in ('vehicle','project') or cat not in ('transport','material','tipp','tipp_deponi','hired','other') or (p_rule->>'target_type'='project' and nullif(trim(p_rule->>'project'),'') is null) then raise exception 'Invalid article allocation';end if;
  if exists(select 1 from public.kpi_workify_article_rules where tenant_id=p_tenant_id and article_number=reference and valid_from>=effective) then raise exception 'Start date must follow existing history';end if;
  update public.kpi_workify_article_rules set valid_to=effective-1 where tenant_id=p_tenant_id and article_number=reference and (valid_to is null or valid_to>=effective);
  insert into public.kpi_workify_article_rules(tenant_id,article_number,project_reference,article_name,target_type,revenue_category,valid_from,valid_to,enabled,source_hash,source_file,source_rows) values(p_tenant_id,reference,case when p_rule->>'target_type'='project' then trim(p_rule->>'project') end,p_rule->>'name',p_rule->>'target_type',cat,effective,ending,true,md5(p_rule::text),'KPI admin dated rule',jsonb_build_array(p_rule||jsonb_build_object('created_by',auth.uid()))) returning id into result;
 elsif p_kind='project_vehicle' then
  if reg !~ '^[A-Z]{3}[0-9]{2}[A-Z0-9]$' then raise exception 'Invalid registration';end if;
  if exists(select 1 from public.kpi_project_vehicle_periods where tenant_id=p_tenant_id and project_reference=reference and valid_from>=effective) then raise exception 'Start date must follow existing history';end if;
  if not exists(select 1 from public.kpi_project_vehicle_periods where tenant_id=p_tenant_id and project_reference=reference) then
   insert into public.kpi_project_vehicle_periods(tenant_id,project_reference,vehicle_registration,valid_from,valid_to,created_by)
   select p_tenant_id,reference,vehicle_registration,coalesce(valid_from,'2000-01-01'),least(coalesce(valid_to,effective-1),effective-1),auth.uid() from public.kpi_project_unit_mappings where tenant_id=p_tenant_id and project_reference=reference and enabled and coalesce(valid_from,'2000-01-01')<effective;
  end if;
  update public.kpi_project_vehicle_periods set valid_to=effective-1 where tenant_id=p_tenant_id and project_reference=reference and (valid_to is null or valid_to>=effective);
  insert into public.kpi_project_vehicle_periods(tenant_id,project_reference,vehicle_registration,valid_from,valid_to,created_by) values(p_tenant_id,reference,reg,effective,ending,auth.uid()) returning id into result;
 elsif p_kind='depreciation' then
  if (p_rule->>'monthly_amount')::numeric<0 or (p_rule->>'monthly_amount')::numeric>10000000 then raise exception 'Invalid monthly amount';end if;
  if exists(select 1 from public.kpi_asset_depreciation_periods where tenant_id=p_tenant_id and object_reference=reference and valid_from>=effective) then raise exception 'Start date must follow existing history';end if;
  update public.kpi_asset_depreciation_periods set valid_to=effective-1 where tenant_id=p_tenant_id and object_reference=reference and (valid_to is null or valid_to>=effective);
  insert into public.kpi_asset_depreciation_periods(tenant_id,object_reference,monthly_depreciation,valid_from,valid_to,source) values(p_tenant_id,reference,(p_rule->>'monthly_amount')::numeric,effective,ending,'kpi_admin_dated') returning id into result;
 else raise exception 'Unknown rule type';end if;
 return result;
end $$;
revoke all on function public.hub_kpi_save_rule_v1(uuid,text,jsonb) from public,anon;
grant execute on function public.hub_kpi_save_rule_v1(uuid,text,jsonb) to authenticated;
