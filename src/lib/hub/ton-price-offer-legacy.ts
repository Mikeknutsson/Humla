import 'server-only';

import type {LegacyOfferSettings} from './ton-price-offer-revision';

async function readPages(bytes: Uint8Array) {
  await import('pdf-parse/worker');
  const {PDFParse} = await import('pdf-parse');
  const parser = new PDFParse({data:bytes});
  try {
    const {pages} = await parser.getText();
    return pages.map(page => page.text);
  } finally {
    await parser.destroy();
  }
}

export async function readLegacyOfferSettings(offer: Uint8Array, plan: Uint8Array): Promise<LegacyOfferSettings> {
  const [offerPages,planPages] = await Promise.all([readPages(offer),readPages(plan)]);
  const header = offerPages[0];
  if (!header?.startsWith('Offert\n') || !planPages[0]?.startsWith('Leveransplan\n')) return {};
  const tip = header.includes('\nTippning inklusive transport\n');
  const projectAddress = tip ? header.match(/^Hämtningsplats (.+)$/m)?.[1] : header.match(/^Leveransplats (.+)$/m)?.[1];
  const date = planPages[0].match(/^Prisdatum (\d{4}-\d{2}-\d{2})$/m)?.[1];
  const validity = header.match(/^Giltig till (\d{4}-\d{2}-\d{2})$/m)?.[1];
  const pricingSources = planPages.flatMap(page => [...page.matchAll(/^Prisgrund (.+)$/gm)].map(match => match[1]));
  const markups = new Set(pricingSources.flatMap(line => {
    const value = line.match(/Materialpåslag ([\d,.]+) %/)?.[1];
    return value === undefined ? [] : [value];
  }));
  const workify = pricingSources.length > 0 && pricingSources.every(line => line.startsWith('Workify STD'));
  const markup = markups.size === 1 && pricingSources.every(line => line.includes('Materialpåslag')) ? [...markups][0] : undefined;

  // A single separately priced truck supplement has its price on the heading.
  // With several supplement rows, their text and the terms cannot safely be separated.
  const termsPage = offerPages.length === 1 ? header.match(
    /^Tillägg enkelbil (?:[\d\s-]+ kr\/ton|Beräknas separat)\nGäller när bil \+ släp ersätts med enkelbil\.\n([\s\S]*?)^Elleholms Maskin AB \| Priser i SEK exkl\. moms/m,
  )?.[1].trim() : undefined;
  return {
    kind:tip ? 'tip' : 'purchase', projectAddress, date, validity,
    pricing:workify || markup !== undefined ? {mode:workify ? 'workify' : 'markup',markup:markup ?? '0',overrides:{}} : undefined,
    terms:termsPage !== undefined && termsPage.length <= 4000 ? termsPage : undefined,
  };
}
