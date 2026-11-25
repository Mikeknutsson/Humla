import Link from 'next/link';
import OfferArchiveControls from './delete-offer-button';
import {offerPdfUrl} from './offer-pdf-url';
import type {readOffers} from '@/lib/hub/ton-price-offer-archive';
import {tonPricePath} from '@/app/_components/kpi-transport-administration-nav';
import styles from './workspace.module.css';

export default function OfferArchive({offers,page,openedId,search,trash}: {
  offers: Awaited<ReturnType<typeof readOffers>>; page: number; openedId?: string; search: string; trash: boolean;
}) {
  function archiveLink(index: number, deleted = trash, revision?: string) {
    const params = new URLSearchParams({offertSida:String(index)});
    if (search) params.set('offertSok',search);
    if (deleted) params.set('offertVy','papperskorg');
    if (revision) params.set('komplettera',revision);
    return `${tonPricePath}?${params}#${revision ? 'komplettering' : 'offertarkiv'}`;
  }
  return <section className="panel" id="offertarkiv">
    <h2>{trash ? 'Papperskorg för offerter' : 'Offertarkiv'}</h2>
    <form action={`${tonPricePath}#offertarkiv`} className={styles.actions}>
      {trash && <input type="hidden" name="offertVy" value="papperskorg"/>}
      <label className={styles.field}>Kund, projekt eller adress
        <input name="offertSok" type="search" defaultValue={search} maxLength={120}/>
      </label>
      <button type="submit" className="secondary">Sök</button>
      <Link href={archiveLink(0,!trash)}>{trash ? 'Till offertarkivet' : 'Papperskorg'}</Link>
    </form>
    {!offers ? <p role="status">Offertarkivet kunde inte hämtas. Försök igen.</p> :
      offers.groups.length ? <div className={styles.archiveGroups}>{offers.groups.map(group => {
        const original = group.entries.find(offer => offer.depth === 0);
        const first = original ?? group.entries[0];
        const title = [first.customer,first.project].filter(Boolean).join(' · ') || first.destinations[0] || 'Offert';
        return <section key={group.group_id} className={styles.card}>
          <h3>{title}</h3>
          <div className={styles.table}><table>
            <thead><tr><th>Offert</th><th>Projektplatser och fraktioner</th><th>Dokument och status</th></tr></thead>
            <tbody>{group.entries.map(offer => <tr key={offer.id}>
              <td>{offer.depth ? 'Komplettering' : 'Original'}<br/><small>{offer.offer_date}</small></td>
              <td>{offer.destinations.join(' · ') || '–'}<br/><small>{offer.materials.join(', ')}</small></td>
              <td>
                {!trash && <div className={styles.actions}>
                  <a href={offerPdfUrl(offer.id,'offert')} download>Offert</a>
                  <a href={offerPdfUrl(offer.id,'leveransplan')} download>Intern leveransplan</a>
                  <Link href={archiveLink(page,false,offer.id)}>Lägg till material</Link>
                </div>}
                <OfferArchiveControls id={offer.id} status={offer.status} trash={trash}
                  back={offer.id === openedId ? archiveLink(page) : undefined}
                  label={`${title} · ${offer.offer_date}`}/>
              </td>
            </tr>)}</tbody>
          </table></div>
        </section>;
      })}</div> : <p>{search ? 'Inga offerter matchar sökningen.' : trash ? 'Papperskorgen är tom.' : page ? 'Inga offerter på den här sidan.' : 'Färdiga offerter och leveransplaner visas här.'}</p>}
    {offers && (page > 0 || offers.hasNext) && <nav aria-label="Sidor i offertarkivet" className={styles.actions}>
      {page > 0 && <Link href={archiveLink(page-1)}>Föregående</Link>}
      <span>Sida {page+1}</span>
      {offers.hasNext && <Link href={archiveLink(page+1)}>Nästa</Link>}
    </nav>}
  </section>;
}
