-- Explicit user review of complete source months for the payment model, not an accounting close.
create table if not exists private.hub_payment_forecast_period_reviews_v1(
 tenant_id uuid not null references public.hub_tenants(id),scope text not null check(scope in('ordinary','stena')),
 center text not null check(center in('20','30','40')),kind text not null check(kind in('in','out')),
 month date not null check(month=date_trunc('month',month)::date),reviewed boolean not null,
 reviewed_by uuid not null,reviewed_at timestamptz not null default now(),note text not null default'',history jsonb not null default'[]',
 primary key(tenant_id,scope,center,kind,month),check(scope<>'stena' or(kind='in'and center<>'40'))
);
alter table private.hub_payment_forecast_period_reviews_v1 add column if not exists source_hash text;
alter table private.hub_payment_forecast_period_reviews_v1 enable row level security;
revoke all on private.hub_payment_forecast_period_reviews_v1 from public,anon,authenticated;
create or replace function private.hub_payment_forecast_reviews_v2(p_tenant uuid,p_scope text default null,p_center text default null,p_kind text default null,p_month date default null,p_reviewed boolean default null,p_note text default'',p_source_hash text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare answer jsonb;event jsonb;
begin
 if auth.uid()is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'Access denied'using errcode='42501';end if;
 if p_reviewed is not null then
  if p_reviewed and(p_source_hash is null or p_source_hash!~'^[a-f0-9]{64}$')then raise exception 'Source fingerprint required';end if;
  if p_scope is null or p_scope not in('ordinary','stena')or p_center is null or p_center not in('20','30','40')or p_kind is null or p_kind not in('in','out')or(p_center='40'and p_kind='in')or(p_scope='stena'and p_kind<>'in')or p_month is null or p_month<>date_trunc('month',p_month)::date or p_month<'2000-01-01' or p_month>=date_trunc('month',(clock_timestamp()at time zone'Europe/Stockholm'))::date or length(coalesce(p_note,''))>500 then raise exception 'Only complete past months and supported source scopes can be reviewed';end if;
  event:=jsonb_build_object('by',auth.uid(),'at',clock_timestamp(),'reviewed',p_reviewed,'note',coalesce(p_note,''),'source_hash',p_source_hash);
  insert into private.hub_payment_forecast_period_reviews_v1(tenant_id,scope,center,kind,month,reviewed,reviewed_by,note,history,source_hash)
  values(p_tenant,p_scope,p_center,p_kind,p_month,p_reviewed,auth.uid(),coalesce(p_note,''),jsonb_build_array(event),p_source_hash)
  on conflict(tenant_id,scope,center,kind,month)do update set reviewed=excluded.reviewed,reviewed_by=excluded.reviewed_by,reviewed_at=now(),note=excluded.note,source_hash=excluded.source_hash,history=hub_payment_forecast_period_reviews_v1.history||excluded.history;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('scope',scope,'center',center,'kind',kind,'month',month,'reviewed',reviewed,'sourceHash',source_hash,'reviewedAt',reviewed_at,'note',note)order by month desc),'[]')into answer from private.hub_payment_forecast_period_reviews_v1 where tenant_id=p_tenant;
 return jsonb_build_object('reviews',answer);
end $$;
revoke all on function private.hub_payment_forecast_reviews_v2(uuid,text,text,text,date,boolean,text,text)from public,anon;
grant execute on function private.hub_payment_forecast_reviews_v2(uuid,text,text,text,date,boolean,text,text)to authenticated;
create or replace function public.hub_payment_forecast_reviews_v2(p_tenant uuid,p_scope text default null,p_center text default null,p_kind text default null,p_month date default null,p_reviewed boolean default null,p_note text default'',p_source_hash text default null)
returns jsonb language sql security invoker set search_path='' as $$select private.hub_payment_forecast_reviews_v2(p_tenant,p_scope,p_center,p_kind,p_month,p_reviewed,p_note,p_source_hash)$$;
revoke all on function public.hub_payment_forecast_reviews_v2(uuid,text,text,text,date,boolean,text,text)from public,anon;
grant execute on function public.hub_payment_forecast_reviews_v2(uuid,text,text,text,date,boolean,text,text)to authenticated;
-- Retire the earlier un-fingerprinted endpoint without dropping functions or audit data.
do $$begin
 if to_regprocedure('public.hub_payment_forecast_reviews_v1(uuid,text,text,text,date,boolean,text)')is not null then
  execute 'revoke all on function public.hub_payment_forecast_reviews_v1(uuid,text,text,text,date,boolean,text) from public,anon,authenticated';
 end if;
 if to_regprocedure('private.hub_payment_forecast_reviews_v1(uuid,text,text,text,date,boolean,text)')is not null then
  execute 'revoke all on function private.hub_payment_forecast_reviews_v1(uuid,text,text,text,date,boolean,text) from public,anon,authenticated';
 end if;
end $$;
