create table private.hub_stena_invoice_refs (
 tenant_id uuid not null,
 file_hash text not null,
 booking text not null,
 invoice_number text not null check(invoice_number ~ '^[0-9]{5,16}$'),
 primary key(tenant_id,file_hash,booking),
 foreign key(tenant_id,file_hash,booking) references private.hub_stena_rows_v1(tenant_id,file_hash,booking) on delete cascade
);
create table private.hub_stena_payout_dates (
 tenant_id uuid not null,
 invoice_number text not null,
 payment_date date not null,
 attachment_id uuid not null references public.hub_gmail_attachments(id),
 primary key(tenant_id,invoice_number)
);
alter table private.hub_stena_invoice_refs enable row level security;
alter table private.hub_stena_payout_dates enable row level security;

do $migration$
declare definition text;
 marker constant text:=' update private.hub_stena_files_v1 set complete=true where tenant_id=p_tenant and file_hash=p_hash;';
begin
 definition:=pg_get_functiondef('private.hub_stena_upload_v1(uuid,text,text,text,jsonb,text,jsonb,boolean)'::regprocedure);
 if strpos(definition,marker)=0 then raise exception 'Stena upload function has changed'; end if;
 execute replace(definition,marker,marker||$capture$
 if p_kind='settled' then
  insert into private.hub_stena_invoice_refs(tenant_id,file_hash,booking,invoice_number)
  select p_tenant,p_hash,r.booking,r.invoice_number from jsonb_to_recordset(p_rows) r(booking text,invoice_number text)
  where r.invoice_number ~ '^[0-9]{5,16}$';
 end if;
$capture$);
end
$migration$;

create function public.hub_stena_record_payout(p_tenant uuid,p_attachment uuid,p_invoice text,p_date date)
returns integer language plpgsql security definer set search_path='' as $$
declare matches integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage') then
  raise exception 'Access denied' using errcode='42501'; end if;
 if p_invoice is null or p_invoice !~ '^[0-9]{5,16}$' or p_date is null
  or p_date not between date '2000-01-01' and date '2099-12-31'
  or not exists(select 1 from public.hub_gmail_attachments a where a.tenant_id=p_tenant and a.id=p_attachment
    and a.status='stored' and a.filename=p_invoice||'.pdf' and a.subject ilike '%Stena Recycling%')
 then raise exception 'Invalid Stena invoice evidence' using errcode='22023'; end if;
 select count(distinct r.booking) into matches from private.hub_stena_invoice_refs r
 join private.hub_stena_files_v1 f using(tenant_id,file_hash)
 where r.tenant_id=p_tenant and r.invoice_number=p_invoice and f.source_kind='settled' and f.complete;
 if matches=0 then return 0; end if;
 insert into private.hub_stena_payout_dates(tenant_id,invoice_number,payment_date,attachment_id)
 values(p_tenant,p_invoice,p_date,p_attachment)
 on conflict(tenant_id,invoice_number) do update set attachment_id=excluded.attachment_id
 where hub_stena_payout_dates.payment_date=excluded.payment_date;
 if not found then raise exception 'Conflicting Stena payout dates' using errcode='23505'; end if;
 return matches;
end;
$$;

create function public.hub_stena_forecast_payouts(p_tenant uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare payout jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage') then
  raise exception 'Access denied' using errcode='42501'; end if;
 with latest as (
  select distinct on(r.revenue_object_id) r.booking, i.invoice_number
  from private.hub_stena_rows_v1 r join private.hub_stena_files_v1 f using(tenant_id,file_hash)
  left join private.hub_stena_invoice_refs i using(tenant_id,file_hash,booking)
  where r.tenant_id=p_tenant and f.complete and f.source_kind='settled'
  order by r.revenue_object_id,f.uploaded_at desc,f.file_hash
 )
 select coalesce(jsonb_object_agg(b.booking,d.payment_date),'{}'::jsonb) into payout
 from latest b join private.hub_stena_payout_dates d on d.tenant_id=p_tenant and d.invoice_number=b.invoice_number;
 return payout;
end;
$$;
revoke all on function public.hub_stena_record_payout(uuid,uuid,text,date),public.hub_stena_forecast_payouts(uuid) from public,anon,authenticated;
grant execute on function public.hub_stena_record_payout(uuid,uuid,text,date),public.hub_stena_forecast_payouts(uuid) to authenticated;
