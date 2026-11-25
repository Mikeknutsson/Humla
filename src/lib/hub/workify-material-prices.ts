import 'server-only';
import type {WorkifyOfferPrice} from './ton-price-offer';
import type {reviewAccess} from './review-access';

export async function readWorkifyMaterialPrices(access: NonNullable<Awaited<ReturnType<typeof reviewAccess>>>) {
  const {data,error} = await access.db.from('hub_workify_standard_material_prices')
    .select('article_number,article_name,material,price,includes_freight')
    .eq('tenant_id',access.tenantId).eq('unit_verified',true).order('includes_freight').order('article_number');
  if (error) return null;
  return data.map(row => ({
    article:row.article_number, label:row.article_name, material:row.material,
    price:Number(row.price), includesFreight:row.includes_freight,
  })) satisfies WorkifyOfferPrice[];
}
