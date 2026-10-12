create or replace function public.hub_kpi_economic_reconciliation_v3(p_tenant_id uuid,p_from date,p_to date,p_filters jsonb default '{}',p_page integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' set statement_timeout='45s' set jit='off' set work_mem='64MB' as $$
declare result jsonb; status_filter text:=coalesce(p_filters->>'status','included');
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 if status_filter not in ('all','included','excluded_duplicate','excluded_withdrawn','excluded_accounted_elsewhere','invalid_economic_data') then raise exception 'Invalid status';end if;
 if p_page is null or p_page<0 or p_page>100000 then raise exception 'Invalid page';end if;
 with facts as materialized(select * from private.hub_economic_transactions_v2(p_tenant_id,p_from,p_to)),
 totals as(select source_family,kind,currency,economic_status,count(*) rows,coalesce(sum(amount)filter(where amount::text not in ('NaN','Infinity','-Infinity')),0) amount from facts group by 1,2,3,4),
 allocations as(select source_family,kind,currency,allocation_status,count(*) rows,coalesce(sum(amount),0) amount from facts where economic_status='included' group by 1,2,3,4),
 controls as(select kind,currency,count(*) rows,coalesce(sum(amount)filter(where amount::text not in ('NaN','Infinity','-Infinity')),0) original_amount from facts group by 1,2),
 items as(select f.*,b.file_name,b.id batch_id,r.row_number
 from facts f join public.kpi_import_rows r on r.id=f.row_id and r.tenant_id=p_tenant_id
 join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=p_tenant_id
 where status_filter='all' or economic_status=status_filter order by occurred_on,row_id limit 100 offset p_page*100)
 select jsonb_build_object('engineVersion','hub-economic-v2','mode','comparison_only','from',p_from,'to',p_to,
 'totals',coalesce((select jsonb_agg(to_jsonb(t) order by kind,currency,economic_status)from totals t),'[]'),
 'includedRows',(select count(*) from facts where economic_status='included'),
 'unallocatedRows',(select count(*)from facts where economic_status='included' and allocation_status<>'verified'),
 'selectedStatus',status_filter,'selectedRows',(select count(*)from facts where status_filter='all' or economic_status=status_filter),
 'allocationTotals',coalesce((select jsonb_agg(to_jsonb(a))from allocations a),'[]'),
 'sourceControls',coalesce((select jsonb_agg(to_jsonb(c))from controls c),'[]'),
 'totalScope','Imported financial source rows, not company result: no payroll estimates, Piusi allocation or internal eliminations',
 'unknownIdentityRows',(select count(*)from facts where canonical_key like 'row:%' and economic_status='included'),
 'invalidAmountRows',(select count(*)from facts where amount is null or amount::text in ('NaN','Infinity','-Infinity')),
 'page',p_page,'pageSize',100,'items',coalesce((select jsonb_agg(to_jsonb(i))from items i),'[]')) into result;
 return result;
end $$;
revoke all on function public.hub_kpi_economic_reconciliation_v3(uuid,date,date,jsonb,integer) from public,anon;
grant execute on function public.hub_kpi_economic_reconciliation_v3(uuid,date,date,jsonb,integer) to authenticated;
notify pgrst,'reload schema';

