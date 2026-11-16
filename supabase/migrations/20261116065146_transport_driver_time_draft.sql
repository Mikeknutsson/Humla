create table private.transport_time_drafts (
  tenant_id uuid not null references public.hub_tenants(id),
  person_id uuid not null references public.hub_objects(id),
  started_at timestamp without time zone not null,
  ended_at timestamp without time zone not null,
  break_minutes integer not null,
  vehicle text not null check (length(vehicle) <= 80),
  note text not null check (length(note) <= 500),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, person_id),
  check (ended_at > started_at and ended_at <= started_at + interval '24 hours'),
  check (break_minutes >= 0 and make_interval(mins => break_minutes) < ended_at - started_at)
);
alter table private.transport_time_drafts enable row level security;
revoke all on private.transport_time_drafts from public, anon, authenticated;

create function private.transport_time_draft(t uuid, draft jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  person uuid := private.transport_driver_person(t);
  result jsonb;
begin
  if draft is not null then
    insert into private.transport_time_drafts as d
      (tenant_id, person_id, started_at, ended_at, break_minutes, vehicle, note)
    values (t, person, (draft->>'start')::timestamp, (draft->>'end')::timestamp,
      (draft->>'breakMinutes')::integer, trim(draft->>'vehicle'), trim(draft->>'note'))
    on conflict (tenant_id, person_id) do update set
      started_at=excluded.started_at, ended_at=excluded.ended_at, break_minutes=excluded.break_minutes,
      vehicle=excluded.vehicle, note=excluded.note, updated_at=now();
  end if;
  select jsonb_build_object('start', to_char(started_at, 'YYYY-MM-DD"T"HH24:MI'),
      'end', to_char(ended_at, 'YYYY-MM-DD"T"HH24:MI'), 'breakMinutes', break_minutes,
      'vehicle', vehicle, 'note', note)
    into result from private.transport_time_drafts where tenant_id=t and person_id=person;
  return result;
end $$;
revoke all on function private.transport_time_draft(uuid,jsonb) from public, anon, authenticated;
grant execute on function private.transport_time_draft(uuid,jsonb) to authenticated;

create function public.hub_transport_time_draft(t uuid, draft jsonb default null)
returns jsonb language sql security invoker set search_path='' as $$
  select private.transport_time_draft(t,draft)
$$;
revoke all on function public.hub_transport_time_draft(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.hub_transport_time_draft(uuid,jsonb) to authenticated;
