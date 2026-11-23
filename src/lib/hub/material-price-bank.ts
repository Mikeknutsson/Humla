export type MaterialSite = {
  id: string; name: string; kind: 'quarry' | 'tip' | 'both'; address: string;
  locationNote: string; addressSource: string; mapPlaceId: string;
};
export type SiteRate = {
  id: string; siteId: string; kind: 'purchase' | 'tip'; material: string; unit: string;
  price: number; validFrom: string | null; validTo: string | null; source: string; imported: boolean;
};
export type MaterialPriceBank = {sites: MaterialSite[]; rates: SiteRate[]};

export function effectiveSiteRates(rates: SiteRate[], date: string) {
  const active = rates.filter(rate => (!rate.validFrom || rate.validFrom <= date) && (!rate.validTo || rate.validTo >= date));
  const latestList = new Map<string, string>();
  for (const rate of active) {
    if (rate.imported && (rate.validFrom ?? '') > (latestList.get(rate.siteId) ?? '')) {
      latestList.set(rate.siteId, rate.validFrom ?? '');
    }
  }
  const entries = new Map<string, SiteRate>();
  for (const rate of active) {
    if (rate.imported && (rate.validFrom ?? '') !== (latestList.get(rate.siteId) ?? '')) continue;
    const key = JSON.stringify([rate.siteId, rate.kind, rate.material.toLocaleLowerCase('sv-SE'), rate.unit]);
    const previous = entries.get(key);
    if (!previous || (rate.validFrom ?? '') > (previous.validFrom ?? '') ||
      (rate.validFrom === previous.validFrom && previous.imported && !rate.imported)) entries.set(key, rate);
  }
  return [...entries.values()];
}

export function stockholmDate() {
  return new Intl.DateTimeFormat('sv-SE', {timeZone: 'Europe/Stockholm', year: 'numeric', month: '2-digit', day: '2-digit'}).format(new Date());
}

// Keep washed, dry and classified variants distinct. Retain original list rows in results.
export function comparisonMaterial(rate: SiteRate) {
  const name = rate.material.trim().replace(/(\d)\s*[/–-]\s*(\d)/g,'$1-$2');
  const normalized = name.replace(/\s+SS-EN\s+\d+(?=\s|$)/gi,'').replace(/\s+/g,' ').trim();
  const fraction = normalized.match(/\b\d+-\d+\b/)?.[0];
  if (!fraction) return normalized;
  if (/^makadam (tvättad \d+-\d+|\d+-\d+ tvättad)$/i.test(normalized)) return `Makadam ${fraction} tvättad`;
  if (/\b(tvättad|torr|klass|eller)\b/i.test(normalized)) return normalized;
  if (/^(bärlager|bergkross)\s/i.test(normalized) && /^0-(32|45|63)$/.test(fraction)) return `Bärlager / bergkross ${fraction}`;
  if (/^förstärkning(s(lager)?)?\s/i.test(normalized) || /^bergkross 0-(90|125|150|200)$/i.test(normalized)) return `Förstärkningslager ${fraction}`;
  return normalized;
}
