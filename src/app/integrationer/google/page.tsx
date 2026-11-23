import Link from 'next/link';
import {ArrowLeft, CalendarDays, FileSpreadsheet, FolderOpen, Mail, MapPinned, Route} from 'lucide-react';
import {GoogleMapsProvider} from '@/app/_components/google-maps-provider';
import {googleHubAccess} from '@/lib/hub/google-hub-access';
import {readGoogleMapsConfig} from '@/lib/hub/google-maps-config';
import MapsSettings from './maps-settings';
import styles from './page.module.css';

const proposed = [
  {name:'Google Drive', Icon:FolderOpen, description:'Hämta prislistor från en vald projektmapp och arkivera godkända KMA-dokument och kalkyler där.'},
  {name:'Google Calendar', Icon:CalendarDays, description:'Visa besiktningar, verkstadsbesök och planerade leveranser i en delad kalender.'},
  {name:'Google Sheets', Icon:FileSpreadsheet, description:'Exportera en kalkyl eller en materialavstämning till ett delat blad.'},
  {name:'Route Matrix och Route Optimization', Icon:Route, description:'Jämför många täkter mot en adress i ett anrop och testa hur flera leveranser och returlass kan samordnas.'},
];

const dateTime = new Intl.DateTimeFormat('sv-SE',{dateStyle:'medium',timeStyle:'short',timeZone:'Europe/Stockholm'});

export default async function GoogleHubPage() {
  const access = await googleHubAccess();
  if (!access) return <section className="section"><h1>Google i Humla Hub</h1><p>Aktivt medlemskap krävs.</p></section>;

  const [maps, gmail] = await Promise.all([
    readGoogleMapsConfig(access.db,access.tenantId),
    access.isOwner ? access.db.from('hub_gmail_mailboxes').select('email,enabled,last_success_at,last_error')
      .eq('tenant_id',access.tenantId).maybeSingle() : null,
  ]);
  const mailbox = gmail?.data;
  const mapsStatus = maps.error ? 'Status kunde inte hämtas' : maps.browserKey
    ? 'Nyckel sparad' : maps.source === 'hub' ? 'Avstängd' : 'Nyckel saknas';

  return <>
    <Link href="/integrationer" className="backlink"><ArrowLeft size={15}/> Alla integrationsområden</Link>
    <header className="topbar">
      <div><h1>Google i Humla Hub</h1><p>Hantera Google-tjänster som används av Humlas olika delar.</p></div>
    </header>
    <div className={styles.services}>
      <section className="section">
        <div className={styles.cardTitle}><h2><MapPinned size={20}/> Google Maps</h2><span>{mapsStatus}</span></div>
        <p>Tonpriskalkylen och Prisbanken hämtar samma inställning för karta, adressökning, kartnål och rutt.</p>
        {maps.updatedAt && <p className="mutedcopy">Uppdaterad {dateTime.format(new Date(maps.updatedAt))}</p>}
        {maps.source === 'environment' && <p className="mutedcopy">Nyckeln hämtas från Humlas miljöinställning.</p>}
        {access.isOwner ? <>
          <GoogleMapsProvider browserKey={maps.browserKey}><MapsSettings canManage={!maps.error}/></GoogleMapsProvider>
          <details className={styles.setup}>
            <summary>Så kopplar du Google Maps</summary>
            <ol>
              <li>Välj ett Google Cloud-projekt med fakturering och aktivera Maps JavaScript API, Places API (New) och Routes API.</li>
              <li>Skapa en webbläsarnyckel med webbplatsbegränsning till <code>https://humla-humla.vercel.app/*</code> och API-begränsning till dessa tre API:er.</li>
              <li>Spara nyckeln här och använd kartan och ruttknappen för att testa.</li>
            </ol>
            <a href="https://console.cloud.google.com/apis/credentials" target="_blank" rel="noreferrer">Öppna Google Cloud Credentials</a>
          </details>
        </> : <p className="mutedcopy">Ägarbehörighet krävs för att ändra anslutningen.</p>}
      </section>
      <section className="section">
        <div className={styles.cardTitle}><h2><Mail size={20}/> Gmail dokumentinkorg</h2>
          {access.isOwner && <span>{gmail?.error ? 'Status kunde inte hämtas' : mailbox?.enabled ? 'Import aktiverad' : 'Import avstängd'}</span>}</div>
        <p>Bilagor hämtas genom Humlas befintliga dokumentimport.</p>
        {mailbox?.email && <p>{mailbox.email}</p>}
        {mailbox?.last_success_at && <p className="mutedcopy">Senaste lyckade hämtning {dateTime.format(new Date(mailbox.last_success_at))}</p>}
        {mailbox?.last_error && <p role="status">Senaste hämtningen rapporterade ett fel. Öppna dokumentinkorgen för detaljer.</p>}
        {access.isOwner && <Link href="/integrationer/dokument-ovrigt/gmail">Öppna Gmail-inställningar</Link>}
      </section>
    </div>
    <section className="section">
      <h2>Möjliga nästa kopplingar</h2>
      <div className={styles.services}>
        {proposed.map(({name, Icon, description}) => <div className={styles.proposal} key={name}>
          <h3><Icon size={18}/>{name}</h3><p>{description}</p>
        </div>)}
      </div>
    </section>
  </>;
}
