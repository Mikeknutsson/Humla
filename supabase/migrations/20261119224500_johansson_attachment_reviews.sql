create table private.hub_johansson_reviews (
 tenant_id uuid not null references public.hub_tenants(id),
 document_key text not null,
 report jsonb not null,
 deviations jsonb not null,
 statuses jsonb not null default '{}',
 revision integer not null default 1,
 updated_at timestamptz not null default now(),
 approved_at timestamptz,
 approved_by uuid,
 primary key (tenant_id, document_key)
);
alter table private.hub_johansson_reviews enable row level security;
revoke all on private.hub_johansson_reviews from public, anon, authenticated;

create function public.hub_johansson_review(
 p_tenant uuid, p_action text, p_key text default null, p_revision integer default null,
 p_item text default null, p_state text default null, p_report jsonb default null, p_deviations jsonb default null
)
returns jsonb language plpgsql security definer
set search_path = '' set statement_timeout = '15s' as $$
declare
 actor uuid := auth.uid();
 is_owner boolean;
 saved private.hub_johansson_reviews%rowtype;
 kept jsonb;
begin
 if actor is null or not public.hub_has_permission(p_tenant, 'kpi.manage') then
  raise exception 'Access denied' using errcode = '42501';
 end if;
 select exists (select 1 from public.hub_tenant_members m
  where m.tenant_id=p_tenant and m.user_id=actor and m.status='active' and m.role='owner') into is_owner;
 if p_action is null or p_action not in ('list','get','register','review','approve','reopen') then
  raise exception 'Invalid review action' using errcode = '22023';
 end if;
 if p_action='list' then
  return (select coalesce(jsonb_agg(jsonb_build_object('key',r.document_key,'name',r.report->>'name',
   'source',r.report->'source','updated_at',r.updated_at,'approved_at',r.approved_at) order by r.updated_at desc,r.document_key), '[]')
   from private.hub_johansson_reviews r
   where r.tenant_id=p_tenant and (is_owner or r.document_key like 'file:%'));
 end if;
 if p_key is null or p_key !~ '^(mail:[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}|file:[a-f0-9]{64})$'
    or (p_key like 'mail:%' and not is_owner) then
  raise exception 'Invalid document key or access denied' using errcode = '42501';
 end if;

 if p_action='register' then
  if jsonb_typeof(p_report) is distinct from 'object'
    or jsonb_typeof(p_report->'invoices') is distinct from 'array'
    or jsonb_typeof(p_report->'name') is distinct from 'string'
    or jsonb_typeof(p_deviations) is distinct from 'object'
    or pg_column_size(p_report)+pg_column_size(p_deviations)>6000000 then
   raise exception 'Invalid document report' using errcode = '22023';
  end if;
  if p_key like 'mail:%' and not exists (select 1 from public.hub_gmail_attachments a
   where a.id=substring(p_key from 6)::uuid and a.tenant_id=p_tenant and a.status='stored') then
   raise exception 'Attachment unavailable' using errcode = 'P0002';
  end if;
  insert into private.hub_johansson_reviews(tenant_id,document_key,report,deviations)
  values(p_tenant,p_key,p_report,p_deviations) on conflict do nothing;
 end if;

 select * into saved from private.hub_johansson_reviews
 where tenant_id=p_tenant and document_key=p_key for update;
 if not found then raise exception 'Document unavailable' using errcode = 'P0002'; end if;

 if p_action='register' then
  -- An approved report is the exact snapshot that was signed off.
  if saved.approved_at is null and (saved.report,saved.deviations) is distinct from (p_report,p_deviations) then
   select coalesce(jsonb_object_agg(k,v), '{}') into kept from jsonb_each(saved.statuses) s(k,v)
    where p_deviations->k = saved.deviations->k;
   update private.hub_johansson_reviews set report=p_report,deviations=p_deviations,statuses=kept,
    revision=revision+1,updated_at=now() where tenant_id=p_tenant and document_key=p_key returning * into saved;
  end if;
 elsif p_action <> 'get' then
  if p_revision is distinct from saved.revision then
   raise exception 'Review changed' using errcode='40001';
  end if;
  if p_action='review' and saved.approved_at is null and p_item is not null
    and saved.deviations ? p_item and p_state in ('todo','in_progress','reviewed') then
   update private.hub_johansson_reviews set
    statuses=jsonb_set(statuses,array[p_item],jsonb_build_object('state',p_state,'by',actor,'at',now())),
    revision=revision+1,updated_at=now() where tenant_id=p_tenant and document_key=p_key returning * into saved;
  elsif p_action='approve' and saved.approved_at is null then
   if exists (select 1 from jsonb_object_keys(saved.deviations) k
    where (saved.statuses->k->>'state') is distinct from 'reviewed') then
    raise exception 'There are open deviations' using errcode='23514';
   end if;
   update private.hub_johansson_reviews set approved_at=now(),approved_by=actor,
    revision=revision+1,updated_at=now() where tenant_id=p_tenant and document_key=p_key returning * into saved;
  elsif p_action='reopen' and saved.approved_at is not null then
   update private.hub_johansson_reviews set approved_at=null,approved_by=null,
    revision=revision+1,updated_at=now() where tenant_id=p_tenant and document_key=p_key returning * into saved;
  else
   raise exception 'Invalid review action' using errcode='22023';
  end if;
 end if;
 return saved.report || jsonb_build_object('key',saved.document_key,'revision',saved.revision,
  'updated_at',saved.updated_at,'approved_at',saved.approved_at,'statuses',saved.statuses);
end
$$;
revoke all on function public.hub_johansson_review(uuid,text,text,integer,text,text,jsonb,jsonb) from public, anon;
grant execute on function public.hub_johansson_review(uuid,text,text,integer,text,text,jsonb,jsonb) to authenticated;
