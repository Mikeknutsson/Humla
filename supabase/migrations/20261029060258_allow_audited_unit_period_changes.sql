alter table public.kpi_unit_initial_setup_events
 drop constraint kpi_unit_initial_setup_events_action_check;
alter table public.kpi_unit_initial_setup_events
 add constraint kpi_unit_initial_setup_events_action_check
 check(action in ('create_initial','correct_initial','lock_initial','extend_history','retroactive_period_change'));