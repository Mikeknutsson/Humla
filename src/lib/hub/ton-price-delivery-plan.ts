import type {MaterialSite} from './material-price-bank';
import type {calculateRound, Round} from './ton-price';

export type DeliveryPlanLine = {
  material: string;
  pickup: string;
  delivery: string;
  tip: boolean;
  tippingDestination?: boolean;
  route: string;
  returnLoad: string;
  purchase: number;
  materialPrice: number;
  freight: number;
  unitPrice: number;
  truckSupplement: number | null;
};

const decimal = new Intl.NumberFormat('sv-SE', {maximumFractionDigits:2});

function place(address: string, site?: MaterialSite) {
  const value = address.trim() || site?.address.trim();
  if (!site) return value || 'Plats saknas';
  return value && value !== site.name ? site.name + ' · ' + value : site.name;
}

export function deliveryPlanRoute(
  round: Round, time: NonNullable<ReturnType<typeof calculateRound>>, vehicle: string, sites: Map<string,MaterialSite>,
) {
  const pickup = place(round.pickup, sites.get(round.pickupSiteId ?? ''));
  const delivery = place(round.delivery, sites.get(round.deliverySiteId ?? ''));
  const returns = round.returnLoad;
  const fields = [vehicle, decimal.format(time.miles)+' mil', decimal.format(time.minutes)+' min per runda'];
  if (!round.mirror && round.returnTo.trim()) fields.push('Retur till '+round.returnTo.trim());
  return {
    pickup,
    delivery,
    route:fields.join(' · '),
    returnLoad:returns && time.returnTonnes > 0
      ? [returns.material.trim() || 'Fraktion saknas', decimal.format(time.returnLoadWeight)+' ton per returlass',
        returns.share+' % av rundorna'].join(' · ')
      : '',
  };
}
