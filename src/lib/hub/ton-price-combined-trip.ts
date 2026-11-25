import type {QuarryQuoteOption} from './quarry-comparison';
import {calculateStartLeg, type Leg} from './ton-price';

export function compareCombinedTrip(delivery: QuarryQuoteOption, tipping: QuarryQuoteOption, tipToQuarry: Leg) {
  const returnLeg = calculateStartLeg({...delivery.round,start:tipToQuarry});
  const deliveryTrips = delivery.trips ?? 0;
  const tippingTrips = tipping.trips ?? 0;
  if (!returnLeg || deliveryTrips <= 0 || tippingTrips <= 0 || delivery.round.returnLoad || tipping.round.returnLoad) return null;

  const pairs = Math.min(deliveryTrips,tippingTrips);
  const toProject = delivery.time.outbound;
  const additionalTipStart = tippingTrips > pairs ? toProject : {miles:0,minutes:0};
  const difference = (key: 'miles' | 'minutes') => {
    const separate = delivery.time.start[key] + deliveryTrips*delivery.time[key] +
      tipping.time.start[key] + tippingTrips*tipping.time[key];
    // Every paired cycle replaces the two empty returns with the single tip-to-quarry leg.
    // If tipping continues after the last delivery loop, the truck is repositioned from the quarry once.
    const combined = separate - tipping.time.start[key] -
      pairs*(delivery.time.inbound[key]+tipping.time.inbound[key]-returnLeg[key]) + additionalTipStart[key];
    return {separate,combined,saved:separate-combined};
  };
  return {pairs,miles:difference('miles'),minutes:difference('minutes')};
}
