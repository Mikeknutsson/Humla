insert into public.hub_connector_definitions
 (code,name,connector_family,adapter_key,transport,auth_type,default_base_url,credential_schema,documentation_url)
values ('gmail_documents','Gmail dokumentimport','documents','gmail_documents_v1','email','oauth2','https://gmail.googleapis.com',
 '{"fields":[{"name":"client_id"},{"name":"client_secret"},{"name":"refresh_token"}]}'::jsonb,
 'https://developers.google.com/workspace/gmail/api/auth/web-server')
on conflict(code,version) do nothing;

create table public.hub_gmail_mailboxes (
 connection_id uuid primary key references public.hub_connections(id),
 tenant_id uuid not null references public.hub_tenants(id),
 email text not null check(email='humlaimport@gmail.com'),
 enabled boolean not null default false,
 start_on date not null default current_date,
 scan_after bigint,
 page_token text,
 scan_until bigint,
 last_success_at timestamptz,
 last_error text,
 lease_until timestamptz,
 lease_id uuid,
 unique(tenant_id,email)
);
create table public.hub_gmail_attachments (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.hub_tenants(id),
 connection_id uuid not null references public.hub_gmail_mailboxes(connection_id),
 message_id text not null,
 part_id text not null,
 filename text not null,
 mime_type text not null,
 sender text,
 subject text,
 received_at timestamptz not null,
 byte_size bigint,
 sha256 text,
 document_id uuid references public.hub_documents(id),
 status text not null default 'pending' check(status in ('pending','stored','unsupported','error')),
 error text,
 created_at timestamptz not null default now(),
 unique(connection_id,message_id,part_id)
);
create index on public.hub_gmail_attachments(tenant_id,received_at desc);
create table private.hub_gmail_oauth_states (
 state text primary key,
 connection_id uuid not null references public.hub_gmail_mailboxes(connection_id),
 verifier text not null,
 expires_at timestamptz not null
);
alter table private.hub_gmail_oauth_states enable row level security;
alter table public.hub_gmail_mailboxes enable row level security;
alter table public.hub_gmail_attachments enable row level security;
revoke all on public.hub_gmail_mailboxes,public.hub_gmail_attachments from anon,authenticated;
grant select on public.hub_gmail_mailboxes,public.hub_gmail_attachments to authenticated;
grant all on public.hub_gmail_mailboxes,public.hub_gmail_attachments to service_role;
create policy gmail_mailbox_owner_read on public.hub_gmail_mailboxes for select to authenticated
 using(exists(select 1 from public.hub_tenant_members m where m.tenant_id=hub_gmail_mailboxes.tenant_id and m.user_id=auth.uid() and m.role='owner' and m.status='active'));
create policy gmail_attachment_owner_read on public.hub_gmail_attachments for select to authenticated
 using(exists(select 1 from public.hub_tenant_members m where m.tenant_id=hub_gmail_attachments.tenant_id and m.user_id=auth.uid() and m.role='owner' and m.status='active'));

create function public.hub_gmail_oauth_state_v1(p_state text,p_connection uuid default null,p_verifier text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare row private.hub_gmail_oauth_states;
begin
 delete from private.hub_gmail_oauth_states where expires_at<now();
 if p_connection is not null then
  insert into private.hub_gmail_oauth_states values(p_state,p_connection,p_verifier,now()+interval '10 minutes');
  return '{}'::jsonb;
 end if;
 delete from private.hub_gmail_oauth_states where state=p_state and expires_at>now() returning * into row;
 if not found then raise exception 'Expired connection request'; end if;
 return to_jsonb(row);
end $$;
create function public.hub_gmail_claim_v1(p_connection uuid,p_lease uuid)
returns boolean language sql security definer set search_path='' as $$
 with claimed as (
 update public.hub_gmail_mailboxes set lease_id=p_lease,lease_until=now()+interval '4 minutes'
 where connection_id=p_connection and enabled and (lease_until is null or lease_until<now())
 returning 1) select exists(select 1 from claimed);
$$;
revoke all on function public.hub_gmail_oauth_state_v1(text,uuid,text),public.hub_gmail_claim_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function public.hub_gmail_oauth_state_v1(text,uuid,text),public.hub_gmail_claim_v1(uuid,uuid) to service_role;

insert into public.hub_connections(tenant_id,name,connector_type,status,connector_definition_id,configuration)
select t.id,'Gmail dokumentimport','gmail_documents','draft',d.id,'{"email":"humlaimport@gmail.com"}'::jsonb
from public.hub_tenants t cross join public.hub_connector_definitions d
where t.name='Elleholms Maskin AB'
and d.code='gmail_documents' and d.version=1
on conflict(tenant_id,name) do nothing;
insert into public.hub_gmail_mailboxes(connection_id,tenant_id,email)
select id,tenant_id,'humlaimport@gmail.com' from public.hub_connections where connector_type='gmail_documents'
on conflict do nothing;

select cron.schedule('gmail-document-import','*/5 * * * *',$cron$
 select net.http_post(
 url:='https://vuurtaafxvevbhdzgttq.supabase.co/functions/v1/gmail-document-import',
 headers:=jsonb_build_object('Content-Type','application/json','x-humla-worker-key',
 (select decrypted_secret from vault.decrypted_secrets where name='humla_worker_key' limit 1)),
 body:='{"action":"sync"}'::jsonb,timeout_milliseconds:=120000);
$cron$);
