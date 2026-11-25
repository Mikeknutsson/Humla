export type MaterialSite = {
  id: string; name: string; kind: 'quarry' | 'tip' | 'both'; address: string;
  locationNote: string; addressSource: string; mapPlaceId: string;
};
export type SiteRate = {
  id: string; siteId: string; kind: 'purchase' | 'tip'; material: string; unit: string;
  price: number; validFrom: string | null; validTo: string | null; source: string; imported: boolean;
};
export type MaterialPriceBank = {sites: MaterialSite[]; rates: SiteRate[]};
const sortergardenPriceList = 'Prislista Sortergården 2026.pdf';

export function effectiveSiteRates(rates: SiteRate[], date: string) {
  const active = rates.filter(rate => (!rate.validFrom || rate.validFrom <= date) && (!rate.validTo || rate.validTo >= date));
  const sitesWithSpecifiedSoil = new Set(active.filter(rate => rate.kind === 'tip' &&
    rate.material === 'Schaktmassor rena (MRR)' && rate.source.startsWith(sortergardenPriceList)).map(rate => rate.siteId));
  const latestList = new Map<string, string>();
  for (const rate of active) {
    if (rate.imported && (rate.validFrom ?? '') > (latestList.get(rate.siteId) ?? '')) {
      latestList.set(rate.siteId, rate.validFrom ?? '');
    }
  }
  const entries = new Map<string, SiteRate>();
  for (const rate of active) {
    if (rate.imported && (rate.validFrom ?? '') !== (latestList.get(rate.siteId) ?? '')) continue;
    if (rate.kind === 'tip' && rate.material === 'Schakt (Pukavik)' && sitesWithSpecifiedSoil.has(rate.siteId)) continue;
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

export const materialGroups = ['Standard','Återvinningsmaterial','Naturgrus','Special','Tippavgifter'] as const;
const [standard,recycled,naturalGravel,special,tipping] = materialGroups;
type MaterialGroup = typeof materialGroups[number];
const sortergardenProducts = new Set([
  'matjord 0-8','anläggningsjord 0-16','lövflis 20-70','grovfyll 0-90','finfyll 0-30',
]);

export const standardMaterialNames: readonly string[] = [
  'Stenmjöl 0-2','Stenmjöl 0-4','Slitlager 0-16','Bärlager 0-32','Bärlager 0-45','Bärlager 0-63',
  'Förstärkningslager 0-90','0-125/150','Råberg','Makadam 2-5','Makadam 4-8','Makadam 8-11',
  'Makadam 11-16','Makadam 16-22','Makadam 32-64',
];

// Bare fractions in the existing purchase lists use the same grades as the named rows.
const fractionNames = new Map<string,string>([
  ...['32','45','63'].map(size => ['0-'+size,'Bärlager 0-'+size] as const),
  ...['2','4','5','8'].map(size => ['0-'+size,'Stenmjöl 0-'+size] as const),
  ...['2-5','4-8','5-8','8-11','8-16','11-16','16-22','16-32','32-64','40-90','100-200']
    .map(fraction => [fraction,'Makadam '+fraction] as const),
  ['0-16','Bergkross 0-16'], ['0-90','Förstärkningslager 0-90'],
]);

const families: [prefix: RegExp, label: string, group: MaterialGroup][] = [
  [/^bärlager\b/i, 'Bärlager', special],
  [/^förstärkning(?:slager)?\b/i, 'Förstärkningslager', special],
  [/^slitlager\b/i, 'Slitlager', special],
  [/^bergkross\b/i, 'Bergkross', special],
  [/^krossgrus\b/i, 'Krossgrus', special],
  [/^makadam\b/i, 'Makadam', special],
  [/^stenmjöl\b/i, 'Stenmjöl', special],
  [/^natur\s*singel\b/i, 'Natursingel', naturalGravel],
  [/^bakbar sandlådesand\b/i, 'Bakbar sandlådesand', naturalGravel],
  [/^dränering\b/i, 'Dränering', naturalGravel],
  [/^gjutgrus\b/i, 'Gjutgrus', naturalGravel],
  [/^murgrus\b/i, 'Murgrus', naturalGravel],
  [/^rörgrus\s*\/\s*kabelsand\b/i, 'Rörgrus/kabelsand', naturalGravel],
  [/^tvättad\b/i, 'Tvättad', naturalGravel],
  [/^grov\s*fyllnad\b/i, 'Grovfyllnad', special],
  [/^fyllnadsmaterial\b/i, 'Fyllnadsmaterial', special],
  [/^moränfyllnad\b/i, 'Moränfyllnad', special],
  [/^matjord\b/i, 'Matjord', special],
  [/^råberg\b/i, 'Råberg', special],
  [/^asfaltkross\b|^asfaltskross\b/i, 'Asfaltskross', recycled],
  [/^betongkross\b/i, 'Betongkross', recycled],
  [/^naturgrus\b/i, 'Naturgrus', naturalGravel],
  [/^sand\b/i, 'Sand', naturalGravel],
  [/^kullersten\b/i, 'Kullersten', naturalGravel],
  [/^stengärdsten\b/i, 'Stengärdsten', naturalGravel],
];

export function standardMaterial(rate: Pick<SiteRate,'material'|'kind'>): {name: string; group: MaterialGroup} {
  const normalized = rate.material.normalize('NFC').trim()
    .replace(/(\d)\s*[/–—−-]\s*(\d)/g,'$1-$2')
    .replace(/\s+SS[- ]EN\s+\d+(?=\s|$)/gi,'')
    .replace(/\s+/g,' ');
  if (rate.kind === 'tip') {
    return {name:/^schakt(?: \(pukavik\))?$/i.test(normalized) ? 'Schakt' : normalized,group:tipping};
  }

  if (/^(?:(?:förstärkning(?:slager)?|bergkross) )?(?:0-(?:125|150)|0-125-150|0-125 eller 0-150|0-150 eller 0-125)$/i.test(normalized)) {
    return {name:'0-125/150',group:standard};
  }

  let name = fractionNames.get(normalized) ?? normalized;
  if (/^bergkross 0-(32|45|63)$/i.test(name)) name = name.replace(/^bergkross/i,'Bärlager');
  if (/^bergkross 0-(90|200)$/i.test(name)) name = name.replace(/^bergkross/i,'Förstärkningslager');
  name = name
    .replace(/^makadam tvättad (\d+-\d+)$/i,'Makadam $1 tvättad')
    .replace(/^tvättad \((dresss?and|fallsand)\) (.+)$/i,(_, sand: string, size: string) =>
      (sand.toLowerCase() === 'fallsand' ? 'Fallsand' : 'Dressand') + ' ' + size + ' tvättad')
    .replace(/\b(Tvättad|Torr|Klass|Diabas|Terminal|Svart|Special)\b/gi,word => word.toLocaleLowerCase('sv-SE'));
  if (/^(dressand|fallsand)\b/i.test(name)) return {name,group:naturalGravel};
  const family = families.find(([pattern]) => pattern.test(name));
  if (family) name = name.replace(family[0],family[1]);
  const group = standardMaterialNames.includes(name) ? standard :
    sortergardenProducts.has(name.toLocaleLowerCase('sv-SE')) ||
    /(?:^|\s)återvunn(?:en|et|a)\b|^återvinningsmaterial\b/i.test(name) ? recycled : family?.[2] ?? special;
  return {name,group};
}

export function compareMaterialFractions(a: string,b: string) {
  function fraction(name: string) {
    return name.match(/\b(\d+(?:[,.]\d+)?)-(\d+(?:[,.]\d+)?)\b/)?.slice(1,3)
      .map(value => Number(value.replace(',','.')));
  }
  const left = fraction(a);
  const right = fraction(b);
  if (left && right) {
    const sizeDifference = left[0]-right[0] || left[1]-right[1];
    if (sizeDifference) return sizeDifference;
  } else if (left || right) return left ? -1 : 1;
  return a.localeCompare(b,'sv',{numeric:true});
}

export function comparisonMaterial(rate: SiteRate) {
  return standardMaterial(rate).name;
}

export function sortergardenSiteIds(sites: MaterialSite[], rates: SiteRate[]) {
  const ids = new Set(rates.filter(rate => rate.source.startsWith(sortergardenPriceList)).map(rate => rate.siteId));
  for (const site of sites) {
    if (site.name === 'Sortergården Pukavik') ids.add(site.id);
  }
  return ids;
}
