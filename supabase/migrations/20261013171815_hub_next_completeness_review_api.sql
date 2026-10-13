create function public.hub_next_completeness_review_v1(p_tenant_id uuid,p_page integer default 0,p_state text default 'all')
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='30s' set jit='off' as $$
declare result jsonb;run record;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 if p_page is null or p_page<0 or p_page>100000 or p_state is null or p_state not in('all','current_scope','candidate_include_unallocated','included_unallocated','reexport','ignored_zero','source_policy_review','account_rule_review','validation_review','invalid_economic','withdrawn','batch_review') then raise exception 'Invalid NEXT review selection';end if;
 select * into run from private.hub_next_completeness_runs where tenant_id=p_tenant_id order by verified_at desc nulls first,id limit 1;
 with source as materialized(select * from private.hub_next_completeness_rows_v1(p_tenant_id)),
 facts as materialized(select s.*,case when r.status='verified' then 'included_unallocated' else s.review_state end state
 from source s left join private.hub_next_completeness_items i on i.row_id=s.row_id and i.tenant_id=p_tenant_id
 left join private.hub_next_completeness_runs r on r.id=i.run_id),
 selected as materialized(select * from facts where p_state='all' or state=p_state),
 items as(select s.*,b.file_name from selected s join public.kpi_import_batches b on b.id=s.batch_id
 order by s.occurred_on nulls first,s.batch_id,s.row_number,s.row_id limit 100 offset p_page*100),
 totals as(select state,currency,count(*) rows,coalesce(sum(amount)filter(where amount::text not in('NaN','Infinity','-Infinity')),0)::text amount from facts group by state,currency),
 accounts as(select account,min(source_data->>'Kontobeskrivning') description,currency,count(*) rows,sum(amount)::text amount from facts where state='account_rule_review' group by account,currency)
 select jsonb_build_object('scope','all_import_history','totalRows',(select count(*)from facts),'selectedRows',(select count(*)from selected),
 'activation',case when run.id is null then null else jsonb_build_object('active',run.status='verified','rows',run.expected_rows,'amount',run.expected_amount::text,'difference',run.result->'difference') end,
 'totals',coalesce((select jsonb_agg(to_jsonb(t)order by state,currency)from totals t),'[]'),
 'accounts',coalesce((select jsonb_agg(to_jsonb(a)order by account,currency)from accounts a),'[]'),
 'items',coalesce((select jsonb_agg((to_jsonb(i)-'amount'-'review_state')||jsonb_build_object('amount',i.amount::text))from items i),'[]')) into result;
 return result;
end $$;
revoke all on function public.hub_next_completeness_review_v1(uuid,integer,text) from public,anon;
grant execute on function public.hub_next_completeness_review_v1(uuid,integer,text) to authenticated;
