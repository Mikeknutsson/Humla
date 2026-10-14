-- Display a Hub-calculated remainder without changing revenue facts.
create or replace function public.hub_kpi_internal_summary_v1(p_tenant uuid,p_year integer,p_months integer[],p_filters jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path='' set jit='off' as $$
declare result jsonb;revenue numeric;remainder numeric;
begin
 result:=private.hub_kpi_internal_overview_v1(p_tenant,p_year,private.hub_kpi_month_scope_v1(p_year,p_months),p_filters);
 revenue:=(private.hub_kpi_prepared_comparison_v1(p_tenant,p_year,p_months,p_filters)#>>'{metrics,revenue}')::numeric;
 remainder:=(result->>'total')::numeric-(result->>'material')::numeric-(result->>'tipp_deponi')::numeric;
 return result||jsonb_build_object('revenue_basis',revenue,
 'total_percent',round((result->>'total')::numeric/nullif(revenue,0)*100,2),
 'material_percent',round((result->>'material')::numeric/nullif(revenue,0)*100,2),
 'tipp_deponi_percent',round((result->>'tipp_deponi')::numeric/nullif(revenue,0)*100,2),
 'remaining',remainder,'remaining_percent',round(remainder/nullif(revenue,0)*100,2));
end $$;
revoke all on function public.hub_kpi_internal_summary_v1(uuid,integer,integer[],jsonb) from public,anon;
grant execute on function public.hub_kpi_internal_summary_v1(uuid,integer,integer[],jsonb) to authenticated;
