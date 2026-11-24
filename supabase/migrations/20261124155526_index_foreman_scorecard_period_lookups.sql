create index if not exists hub_prepared_foreman_project_period_idx
 on private.hub_kpi_prepared_kpi_project_classification_periods
 (generation_id,tenant_id,project_reference,valid_from desc,id);
create index if not exists hub_prepared_foreman_display_period_idx
 on private.hub_kpi_prepared_display_facts (generation_id,tenant_id,occurred_on);
create index if not exists hub_prepared_foreman_display_transpa_idx
 on private.hub_kpi_prepared_display_facts (generation_id,tenant_id,((original->>'time_report_id')))
 where source='TransPA' and category='personnel';
