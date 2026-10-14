-- Restore the confirmed Workify article destination after an overbroad
-- Dashboard project override. Raw imports remain untouched.
create table if not exists private.hub_trading_destination_audit_v1 (
 operation_id uuid not null, tenant_id uuid not null, generation_id uuid not null,
 record_kind text not null, record_key text not null,
 before_record jsonb not null, after_record jsonb,
 actor uuid not null, recorded_at timestamptz not null default clock_timestamp(),
 primary key(operation_id,record_kind,record_key)
);
alter table private.hub_trading_destination_audit_v1 enable row level security;
revoke all on private.hub_trading_destination_audit_v1 from public,anon,authenticated;

