import Link from 'next/link';
import {offerPdfUrl} from './offer-pdf-url';
import type {readOffers} from '@/lib/hub/ton-price-offer-archive';
import styles from './workspace.module.css';

export default function OfferArchive({offers,page}: {offers: Awaited<ReturnType<typeof readOffers>>; page: number}) {
  return <section className="panel" id="offertarkiv">
    <h2>Offertarkiv</h2>
    {!offers ? <p role="status">Offertarkivet kunde inte hämtas. Ladda om sidan och försök igen.</p> :
      offers.entries.length ? <div className={styles.table}><table>
        <thead><tr><th>Skapad</th><th>Kund och projekt</th><th>Leveransplats</th><th>Fraktioner hittills</th><th>Dokument</th></tr></thead>
        <tbody>{offers.entries.map(offer => <tr key={offer.id}>
          <td>{offer.offer_date}{offer.source_offer_id && <><br/><small>Komplettering</small></>}</td>
          <td>{[offer.customer,offer.project].filter(Boolean).join(' · ') || '–'}</td>
          <td>{offer.destinations.join(' · ') || '–'}</td>
          <td>{offer.materials.join(', ')}</td>
          <td><div className={styles.actions}>
            <a href={offerPdfUrl(offer.id,'offert')} download>Offert</a>
            <a href={offerPdfUrl(offer.id,'leveransplan')} download>Intern leveransplan</a>
            <Link href={`?offertSida=${page}&komplettera=${offer.id}#komplettering`}>Lägg till material</Link>
            {offer.source_offer_id && <a href={offerPdfUrl(offer.source_offer_id,'offert')} download>Föregående offert</a>}
          </div></td>
        </tr>)}</tbody>
      </table></div> : <p>{page ? 'Inga offerter på den här sidan.' : 'Färdiga offerter och leveransplaner visas här när du skapar dem.'}</p>}
    {offers && (page > 0 || offers.hasNext) && <nav aria-label="Sidor i offertarkivet" className={styles.actions}>
      {page > 0 && <Link href={`?offertSida=${page-1}#offertarkiv`}>Föregående</Link>}
      <span>Sida {page+1}</span>
      {offers.hasNext && <Link href={`?offertSida=${page+1}#offertarkiv`}>Nästa</Link>}
    </nav>}
  </section>;
}
