'use server';

import {revalidatePath} from 'next/cache';
import {reviewAccess} from '@/lib/hub/review-access';
import {materialPriceBankPath, tonPricePath} from '@/app/_components/kpi-transport-administration-nav';

export async function savePriceBankEntry(kind: 'site' | 'rate', data: Record<string, string>) {
  const access = await reviewAccess();
  if (!access) return {error: 'Behörighet saknas.'};
  const {data: id, error} = await access.db.rpc('hub_material_price_bank_save', {p_tenant: access.tenantId, p_kind: kind, p_data: data});
  if (error?.code === '23505') return {error: 'Platsen eller prisversionen finns redan.'};
  if (error?.code === '42501') return {error: 'KPI-administratör krävs för att spara.'};
  if (error) return {error: 'Kontrollera plats, pris, enhet och giltighetsdatum.'};
  revalidatePath(materialPriceBankPath);
  revalidatePath(tonPricePath);
  return {saved: true, id: id as string};
}
