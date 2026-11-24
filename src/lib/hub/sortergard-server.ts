import 'server-only';
import {reviewAccess} from './review-access';

export async function yardAccess() {
  const access = await reviewAccess();
  if (!access) return null;
  const {data,error} = await access.db.rpc('hub_has_permission',{p_tenant_id:access.tenantId,p_permission:'kpi.manage'});
  return !error && data === true ? access : null;
}

export function yardReport(access: NonNullable<Awaited<ReturnType<typeof yardAccess>>>, year:number, action:string, args:object = {}) {
  return access.db.rpc('hub_sortergard_report',{p_tenant:access.tenantId,p_year:year,p_action:action,p_args:args});
}

export function reportYear(input?: string) {
  const current = Number(new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Stockholm',year:'numeric'}).format(new Date()));
  const selected = Number(input);
  return Number.isInteger(selected) && selected >= 2026 && selected <= current ? selected : Math.max(2026,current);
}
