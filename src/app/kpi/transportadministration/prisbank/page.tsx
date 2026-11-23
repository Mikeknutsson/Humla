import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {reviewAccess} from '@/lib/hub/review-access';
import {readPriceBank} from '@/lib/hub/material-price-bank-server';
import {stockholmDate} from '@/lib/hub/material-price-bank';
import PriceBankWorkspace from './workspace';

export default async function Page() {
  const access = await reviewAccess();
  const [bank, permission] = access ? await Promise.all([readPriceBank(access),
    access.db.rpc('hub_has_permission', {p_tenant_id: access.tenantId, p_permission: 'kpi.manage'})]) : [null, null];
  return <KpiDetailShell query="" title="Prisbank" breadcrumb="Humla Dashboard / Transportadministration" transportAdministration="price-bank">
    {bank ? <PriceBankWorkspace bank={bank} today={stockholmDate()} canManage={permission?.data === true}/>
      : <div className="content"><section className="panel"><p>{access ? 'Prisbanken kunde inte hämtas.' : 'Behörighet saknas.'}</p></section></div>}
  </KpiDetailShell>;
}
