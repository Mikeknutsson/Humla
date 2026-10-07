-- Fresh generations have no column statistics until auto-analyze catches up.
-- Keep the bulk operational snapshot's hash-join strategy; indexed lookups
-- remain enabled in the monthly wrapper. The financial comparison projection
-- removes the previous-year operational snapshot without unsafe nested loops.
alter function private.hub_kpi_prepared_snapshot_v1(uuid,integer,integer[],jsonb) set enable_nestloop='off';
