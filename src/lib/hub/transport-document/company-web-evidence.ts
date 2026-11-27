export const companyWebDomains = ['allabolag.se','hitta.se','kommersannons.se','ted.europa.eu'];
export type CompanyWebDetails = {organisation:string; address:string; source:string};

export function searchableCompany(value: string) {
  return value.length <= 110 &&
    /^(?:[\p{L}\p{N}][\p{L}\p{M}\p{N} .,&()/+’'-]*\s(?:AB|Aktiebolag|HB|KB|Handelsbolag|Kommanditbolag|Ekonomisk förening|kommun)|Region\s[\p{L}\p{M} -]+)$/iu.test(value);
}

function companyKey(value: string) {
  return value.trim().toLocaleLowerCase('sv').replace(/\s+/g,' ')
    .replace(/\saktiebolag$/,' ab').replace(/\shandelsbolag$/,' hb').replace(/\skommanditbolag$/,' kb');
}

function legalNameMatches(name: string, title: string, excerpt: string) {
  const legalTitles = Array.from(excerpt.matchAll(
    /(?:juridiskt namn|officiellt namn|official name)\s*:?\s*([^\n|]+?)(?=\n|\||\s+(?:org(?:anisations)?[. ]?(?:nr|nummer)|registration number|Postadress)\b|$)/gi),m=>m[1]);
  return [title.split(/\s+[-–|]\s+/)[0],...legalTitles].some(value => companyKey(value) === companyKey(name));
}

function validOrganisation(value: string) {
  const digits = [...value.replace(/\D/g,'')].map(Number);
  return digits.length === 10 && digits[2] >= 2 && digits.reduce((total,digit,index) => {
    const n = index%2 ? digit : 2*digit;
    return total+(n > 9 ? n-9 : n);
  },0)%10 === 0;
}

function organisationNumbers(text: string) {
  return new Set(Array.from(text.matchAll(
    /(?:organisationsnummer|org\.?\s*nr\.?|registreringsnummer|registration number)\s*:?\s*(\d{6}[-\s]?\d{4})(?!\d)/gi),
  m=>m[1]).filter(validOrganisation).map(value=>value.replace(/\D/g,'').replace(/^(\d{6})/,'$1-')));
}

function postalAddress(excerpt: string) {
  const raw = excerpt.match(/(?:^|[^\p{L}])(?:postadress|postal address)\s*:\s*([^]{1,260})|(?:^|[^\p{L}])postadress\s+([^]{1,260})/iu);
  if (!raw) return '';
  const block = (raw[1] ?? raw[2]).split(
    /\s+(?:arbetsställen|se arbetsställen|besöksadress|juridiskt namn|organisationsnummer|org\.?\s*nr|land|country|telefon|e-post|adressändring|registreringsdatum|bolagsform)\b/i,
  )[0].trim();
  const town = block.match(/^([^]+?)\s+(?:town|ort|stad)\s*:\s*([\p{L}\p{M} -]+?)\s+(?:postcode|postnummer)\s*:\s*(\d{3})\s?(\d{2})\b/iu);
  const inline = block.match(/^([^]*?)\b(\d{3})\s?(\d{2})\s+([\p{L}\p{M}][\p{L}\p{M} '-]*(?:[ \t]+[\p{L}\p{M}][\p{L}\p{M} '-]*)?)(?=[\n,.|;]|$)/u);
  const row = town ? [town[1],town[3],town[4],town[2]] : inline?.slice(1);
  if (!row) return '';
  const [street,first,last,city] = row.map(part=>part.trim().replace(/\s+/g,' '));
  if (street.length > 130 || city.length > 42 || city.split(' ').length > 4) return '';
  if (/[<>?]/.test(street) || /…/.test(street)) return '';
  return [street.replace(/,$/,''),`${first} ${last} ${city}`].filter(Boolean).join(', ');
}

export function companyWebDetails(name: string, results: unknown[]): CompanyWebDetails | undefined {
  const candidates = new Map<string,CompanyWebDetails>();
  for (const item of results.slice(0,6)) {
    if (!item || typeof item !== 'object') continue;
    const {title,url,snippet} = item as Record<string,unknown>;
    if (typeof title !== 'string' || typeof url !== 'string' || typeof snippet !== 'string' ||
        url.length > 1500 || !legalNameMatches(name,title,snippet)) continue;
    let source: URL;
    try { source = new URL(url); } catch { continue; }
    if (source.protocol !== 'https:' || source.port || source.username || source.password ||
        !companyWebDomains.some(domain=>source.hostname===domain||source.hostname.endsWith('.'+domain))) continue;
    const numbers = organisationNumbers(title+'\n'+snippet);
    if (numbers.size !== 1) continue;
    const organisation = [...numbers][0];
    const address = postalAddress(snippet);
    if (!address) continue;
    const identity = organisation+'|'+address.toLocaleLowerCase('sv');
    source.hash = '';
    candidates.set(identity,{organisation,address,source:source.href});
  }
  return candidates.size === 1 ? [...candidates.values()][0] : undefined;
}
