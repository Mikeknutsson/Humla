'use server';

import {reviewAccess} from '@/lib/hub/review-access';
import {calculateTonPrices, type TonPriceDraft} from '@/lib/hub/ton-price';

export async function tonPriceAccess() {
  const access = await reviewAccess();
  if (!access) return null;
  const permission = await access.db.rpc('hub_has_permission', {
    p_tenant_id: access.tenantId, p_permission: 'kpi.manage',
  });
  if (permission.error || permission.data !== true) return null;
  const {data: {user}} = await access.db.auth.getUser();
  return user ? {tenantId: access.tenantId, userId: user.id} : null;
}

export async function recalculateTonPrices(draft: TonPriceDraft) {
  if (!await tonPriceAccess()) return {error: 'Behörighet saknas.'};
  if (!draft || !Array.isArray(draft.rounds) || !Array.isArray(draft.materials) ||
    !Array.isArray(draft.vehicles) || draft.rounds.length > 30 || draft.materials.length > 100 ||
    draft.vehicles.length !== 3 || !['reference', 'bk1', 'bk4'].includes(draft.profile)) {
    return {error: 'Kalkylen kunde inte läsas.'};
  }
  try {
    return {result: calculateTonPrices(draft)};
  } catch {
    return {error: 'Kalkylen innehåller ogiltiga värden.'};
  }
}
