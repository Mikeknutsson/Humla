import 'server-only';

import {reviewAccess} from '@/lib/hub/review-access';

export async function tonPriceAccess() {
  const access = await reviewAccess();
  if (!access) return null;
  const permission = await access.db.rpc('hub_has_permission', {
    p_tenant_id: access.tenantId, p_permission: 'kpi.manage',
  });
  if (permission.error || permission.data !== true) return null;
  const {data: {user}} = await access.db.auth.getUser();
  return user ? {...access, userId: user.id} : null;
}
