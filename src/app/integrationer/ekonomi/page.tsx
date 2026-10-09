import Link from 'next/link';
import { NEXT_FINANCE_CONTRACT } from '@/lib/hub/next-finance';

export default function Page() {
  return <>
    <Link href="/integrationer" className="backlink">← Alla integrationsområden</Link>
    <header className="topbar"><div><span className="eyebrow">INTEGRATIONER</span><h1>Ekonomi</h1><p>Ekonomiska transaktioner, kostnader, intäkter och projektdata.</p></div></header>
    <section className="section">
      <span className="label">HUMLA HUB · NeXT API</span>
      <h2>Förberett — inte anslutet</h2>
      <p>Inläsningskontrakt version {NEXT_FINANCE_CONTRACT.version}. Ingen automatisk API-hämtning är aktiverad och inga API-belopp ingår i KPI.</p>
      <h3>Underlag som kopplingen är förberedd för</h3>
      <p>Projekt inklusive avslutade och historiska projekt, bokförda kostnader och intäkter, personalkostnader samt kund- och leverantörsfakturor.</p>
      <h3>Kontroller i Hubben</h3>
      <p>Originalrader och ändringar ska bevaras. NeXT-identiteter kopplas till bekräftade Humla-ID:n. Osäkra projektkopplingar lämnas för granskning. API-data läses först till ett separat avstämningsunderlag och ersätter inte dagens filimporter automatiskt.</p>
      <p>Fakturor ska stämmas av mot bokföringsrader, inte läggas till som en andra intäkt eller kostnad. Transport behåller TransPA som personalkälla; övriga kostnadsställen använder NeXT. Interna körningar behåller befintlig avräkning mot konto 4600.</p>
      <h3>Återstår innan aktivering</h3>
      <p>Verifiera NeXT:s API-fält, läsbehörigheter och paginering; konfigurera API-uppgifter server-side; koppla permanent staginglagring; komplettera historiska projekt och stäm av API-rader mot filunderlaget. Därefter krävs uttrycklig aktivering.</p>
      <p className="mutedcopy">Dashboarden är fortsatt en konsument. API-koppling, projektmatchning och ekonomiska regler hör hemma i Hubben.</p>
    </section>
  </>;
}
