import 'server-only';

import {reviewAccess} from './review-access';
import type {MaterialPriceBank} from './material-price-bank';

export async function readPriceBank(access: NonNullable<Awaited<ReturnType<typeof reviewAccess>>>, forTonPrice = false) {
  const {data, error} = await access.db.rpc(forTonPrice ? 'hub_ton_price_material_bank' : 'hub_material_price_bank', {p_tenant: access.tenantId});
  if (error) {
    console.error('Hub material price bank could not be read', error.code);
    return null;
  }
  return data as MaterialPriceBank;
}
