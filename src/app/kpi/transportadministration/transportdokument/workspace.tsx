'use client';

import {useMemo, useRef, useState, type FormEvent} from 'react';
import {Download, Plus, Trash2} from 'lucide-react';
import {GoogleAddressField, geocodeSwedishAddress, reverseGeocodePoint, type Point} from '@/app/_components/google-address-field';
import {useGoogleMapsKey} from '@/app/_components/google-maps-provider';
import {elleholms, emptyParty, emptyLocation, emptyWaste, municipalityFor, municipalityOptions, receiverOptions,
  type DocumentFields, type HubChoice, type Location, type Party, type Waste} from '@/lib/hub/transport-document/fields';
import {wasteChoices} from '@/lib/hub/transport-document/waste-options';
import {SearchField, type Choice} from './search-field';
import {loadConsignorDetails} from './actions';
import styles from './workspace.module.css';

function PartyFields({party,onChange,choices,onSelect}: {
  party: Party; onChange: (party: Party) => void; choices?: readonly Choice[]; onSelect?: (choice: Choice) => void;
}) {
  return <div className={styles.grid}>
    {choices?.length ? <SearchField label="Namn eller företagsnamn" value={party.name} choices={choices}
      placeholder="Sök eller skriv företagsnamn" maxLength={110} required
      onChange={name => onChange({...party,name})}
      onSelect={onSelect ?? (choice => onChange({...party,name:choice.value}))}/> :
      <label>Namn eller företagsnamn<input value={party.name} maxLength={110} required
        onChange={event => onChange({...party,name:event.target.value})}/></label>}
    <label>Organisations-, person- eller skatteregistreringsnummer<input value={party.organisation} maxLength={30} required
      onChange={event => onChange({...party,organisation:event.target.value})}/></label>
    <label>Postadress<input value={party.address} maxLength={220} required
      onChange={event => onChange({...party,address:event.target.value})}/></label>
  </div>;
}

const municipalities = municipalityOptions.map(([code,name]) => ({value:code,label:`${name} (${code})`}));
const municipalityLabels = new Map(municipalities.map(({value,label}) => [value,label]));
const facilities = receiverOptions.map(receiver => ({
  value:receiver.name,label:receiver.name,keywords:`${receiver.address} ${receiver.organisation}`,
}));
const packaging = ['Flak','Container','Storsäck','Säck','Fat','Dunk','Pall','Löst'].map(value => ({value,label:value}));

function LocationFields({label,location,onChange,onMunicipality}: {
  label: string; location: Location; onChange: (location: Location) => void;
  onMunicipality: (address: string, code: string) => void;
}) {
  const key = useGoogleMapsKey();
  const [place,setPlace] = useState<{value: string; id?: string; point?: Point}>();
  const [status,setStatus] = useState<{value: string; text: string; pending?: boolean}>();
  const sequence = useRef(0);
  const selected = place?.value === location.value ? place : undefined;

  async function lookup(value: string, point?: Point) {
    if (!key || !value.trim()) return;
    const request = ++sequence.current;
    setStatus({value,text:'Hämtar kommunkod…',pending:true});
    try {
      const results = point ? await reverseGeocodePoint(key,point) : await geocodeSwedishAddress(key,value);
      if (sequence.current !== request) return;
      const matches = results.filter(result => !result.partial_match && (point || result.types.some(type =>
        ['street_address','premise','subpremise','establishment','point_of_interest','postal_code','intersection'].includes(type))));
      const codes = [...new Set(matches.map(match => municipalityFor(match.address_components)).filter(Boolean))];
      if (codes.length === 1) onMunicipality(value,codes[0]);
      setStatus({value,text:codes.length === 1 ? 'Kommunkod hämtad.' : 'Välj kommun i listan om koden behövs.'});
    } catch {
      if (sequence.current === request) setStatus({value,text:'Kommunkoden kunde inte hämtas. Du kan välja kommun i listan.'});
    }
  }

  return <fieldset className={styles.fieldset}>
    <legend>{label}</legend>
    <div className={styles.address}>
      <GoogleAddressField label={`Adress eller koordinater för ${label.toLowerCase()}`} value={location.value}
        placeId={selected?.id} point={selected?.point} autocomplete placeholder="Sök adress eller ange latitud, longitud"
        onChange={(value,id,point) => {
          sequence.current += 1;
          setStatus(undefined);
          setPlace({value,id,point});
          onChange({value,municipality:value === location.value ? location.municipality : ''});
          if (point || id) void lookup(value,point);
        }}/>
      {key && <button type="button" className="secondary" disabled={!location.value.trim() || (status?.value === location.value && status.pending)}
        onClick={() => void lookup(location.value,selected?.point)}>Hämta kommunkod</button>}
      {status?.value === location.value && <small role="status">{status.text}</small>}
    </div>
    <SearchField label="Kommun" choices={[{value:'',label:'Ingen kommun vald'},...municipalities]}
      value={municipalityLabels.get(location.municipality) ?? ''} placeholder="Sök kommun eller kommunkod"
      onSelect={({value}) => {
        sequence.current += 1;
        setStatus(undefined);
        onChange({...location,municipality:value});
      }}/>
  </fieldset>;
}

type WasteChoice = ReturnType<typeof wasteChoices>[number];

function WasteFields({row,index,choices,onChange,onRemove}: {
  row: Waste; index: number; choices: WasteChoice[]; onChange: (row: Waste) => void; onRemove?: () => void;
}) {
  return <fieldset className={styles.fieldset}>
    <legend>Avfallsrad {index+1}</legend>
    <div className={styles.grid}>
      <div>
        <SearchField label="Avfallskod" value={row.code} choices={choices} required
          placeholder="Sök avfallskod eller material" onSelect={choice => {
            const oldName = choices.find(option => option.value === row.code)?.name;
            onChange({...row,code:choice.value,name:!row.name || row.name === oldName ? choice.name : row.name});
          }}/>
        {row.code && !choices.some(choice => choice.value === row.code) &&
          <small>Välj en avfallskod som gäller på transportdatumet.</small>}
      </div>
      <label>Benämning<input value={row.name} maxLength={180} required onChange={event => onChange({...row,name:event.target.value})}/></label>
      <label>Uppskattad vikt (kg)<input value={row.estimatedKg} inputMode="decimal" maxLength={18}
        onChange={event => onChange({...row,estimatedKg:event.target.value})}/></label>
      <label>Invägt kg<input value={row.weighedKg} inputMode="decimal" maxLength={18}
        onChange={event => onChange({...row,weighedKg:event.target.value})}/></label>
      <label>Antal kollin<input value={row.packages} inputMode="numeric" maxLength={10} onChange={event => onChange({...row,packages:event.target.value})}/></label>
      <SearchField label="Emballage" value={row.packaging} choices={packaging} maxLength={45}
        onChange={value => onChange({...row,packaging:value})}
        onSelect={({value}) => onChange({...row,packaging:value})}/>
    </div>
    {onRemove && <button type="button" className="secondary" onClick={onRemove} aria-label={`Ta bort avfallsrad ${index+1}`}>
      <Trash2 size={15}/> Ta bort
    </button>}
  </fieldset>;
}

export function DocumentWorkspace({vehicles,customers,customersFailed,profileName,today,vehiclesFailed}: {
  vehicles: HubChoice[]; customers: string[]; customersFailed: boolean;
  profileName: string; today: string; vehiclesFailed: boolean;
}) {
  const [form,setForm] = useState<DocumentFields>(() => ({
    date:today,workifyOrderNumber:'',registration:'',carrier:elleholms,consignor:emptyParty,receiver:emptyParty,
    origin:emptyLocation,destination:emptyLocation,deliveryNumber:'',adrReference:'',waste:[emptyWaste],
    carrierSigner:'',consignorSigner:'',
  }));
  const customerChoices = useMemo(() => customers.map(name => ({value:name,label:name})),[customers]);
  const codes = useMemo(() => wasteChoices(form.date),[form.date]);
  const [exporting,setExporting] = useState(false);
  const [feedback,setFeedback] = useState<{text: string; error?: boolean}>();
  const lastConsignor = useRef<Party>(emptyParty);
  const selectedCustomer = useRef('');
  const lookupVersion = useRef(0);
  const [lookup,setLookup] = useState<{name:string; description:string; source?:string}>();
  const update = <K extends keyof DocumentFields>(key: K, value: DocumentFields[K]) =>
    setForm(draft => ({...draft,[key]:value}));
  const setMunicipality = (field: 'origin' | 'destination') => (value: string, code: string) => setForm(draft =>
    draft[field].value === value ? {...draft,[field]:{value,municipality:code}} : draft);

  async function chooseConsignor(name: string) {
    const sameCustomer = selectedCustomer.current === name;
    selectedCustomer.current = name;
    setForm(draft => ({...draft,consignor:sameCustomer && draft.consignor
      ? {...draft.consignor,name} : {...emptyParty,name}}));
    const version = ++lookupVersion.current;
    setLookup({name,description:'Hämtar kunduppgifter…'});
    try {
      const result = await loadConsignorDetails(name);
      if (version !== lookupVersion.current) return;
      if (result.status === 'found') {
        setForm(draft => draft.consignor?.name === name ? {...draft,consignor:{
          ...draft.consignor, organisation:draft.consignor.organisation || result.organisation,
          address:draft.consignor.address || result.address,
        }} : draft);
        setLookup({name,description:result.organisation && result.address ? 'Kunduppgifter hämtade från Humla Hub.' :
          'En kunduppgift hämtades från Humla Hub. Kontrollera det andra fältet.',source:result.source});
      } else {
        setLookup({name,description:result.status === 'missing' ? 'Kundposten saknar entydiga uppgifter. Fyll i fälten nedan.' :
          'Kunduppgifterna kunde inte hämtas just nu.'});
      }
    } catch {
      if (version === lookupVersion.current) setLookup({name,description:'Kunduppgifterna kunde inte hämtas just nu.'});
    }
  }

  async function download(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setFeedback(undefined);
    setExporting(true);
    try {
      const response = await fetch('/kpi/transportadministration/transportdokument/pdf',{
        method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(form),
      });
      if (!response.ok) {
        const data = await response.json().catch(() => ({})) as {error?: string};
        throw new Error(data.error ?? 'PDF:en kunde inte skapas. Försök igen.');
      }
      const url = URL.createObjectURL(await response.blob());
      const link = document.createElement('a');
      link.href = url;
      const reg = form.registration.trim().replace(/[^A-Z0-9-]/gi,'');
      link.download = ['Transportdokument',form.date,reg].filter(Boolean).join('-')+'.pdf';
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url),30_000);
      setFeedback({text:'PDF:en har laddats ner för utskrift och underskrift.'});
    } catch (error) {
      setFeedback({error:true,text:error instanceof Error ? error.message : 'PDF:en kunde inte skapas.'});
    } finally {
      setExporting(false);
    }
  }

  return <form className={`content ${styles.form}`} onSubmit={download}>
    <section className={`panel ${styles.first}`}>
      <h2>Körning</h2>
      {vehiclesFailed && <p role="status">Lastbilslistan kunde inte hämtas fullständigt. Du kan skriva registreringsnumret manuellt.</p>}
      <div className={styles.grid}>
        <label>Transportdatum<input type="date" value={form.date} required onChange={event => update('date',event.target.value)}/></label>
        <label>Ordernummer Workify<input value={form.workifyOrderNumber} maxLength={50}
          onChange={event => {
            const workifyOrderNumber = event.target.value;
            setForm(draft => ({
              ...draft,workifyOrderNumber,
              deliveryNumber:draft.deliveryNumber && draft.deliveryNumber !== draft.workifyOrderNumber
                ? draft.deliveryNumber : workifyOrderNumber,
            }));
          }}/></label>
        <SearchField label="Registreringsnummer" maxLength={24} value={form.registration} choices={vehicles}
          placeholder="Sök lastbil eller skriv registreringsnummer" onChange={value => update('registration',value)}
          onSelect={({value}) => update('registration',value)}/>
      </div>
    </section>

    <section className="panel">
      <h2>Parter</h2>
      <fieldset className={styles.fieldset}>
        <legend>Transportör</legend>
        <PartyFields party={form.carrier} onChange={value => update('carrier',value)}/>
      </fieldset>
      <fieldset className={styles.fieldset}>
        <legend>Lämnare</legend>
        <label className={styles.checkbox}><input type="checkbox" checked={!form.consignor} onChange={event => {
          lookupVersion.current += 1;
          setLookup(undefined);
          if (form.consignor) lastConsignor.current = form.consignor;
          update('consignor',event.target.checked ? null : lastConsignor.current);
        }}/> Ingen separat lämnare, till exempel vid egen transport av eget avfall</label>
        {form.consignor && <>
          {customersFailed && <p role="status">Kundlistan från Workify kunde inte hämtas fullständigt. Du kan fylla i lämnaren manuellt.</p>}
          {lookup?.name === form.consignor.name && <p role="status">{lookup.description}
            {lookup.source && <> <a href={lookup.source} target="_blank" rel="noreferrer">Visa källa</a></>}
          </p>}
          <PartyFields party={form.consignor} choices={customerChoices} onChange={value => {
            if (value.name !== form.consignor?.name) {
              lookupVersion.current += 1;
              selectedCustomer.current = '';
              setLookup(undefined);
            }
            update('consignor',value);
          }} onSelect={({value}) => void chooseConsignor(value)}/>
        </>}
      </fieldset>
      <fieldset className={styles.fieldset}>
        <legend>Slutlig mottagare</legend>
        <PartyFields party={form.receiver} choices={facilities} onChange={value => update('receiver',value)}
          onSelect={({value}) => {
            const option = receiverOptions.find(receiver => receiver.name === value);
            if (!option) return;
            const {municipality,...receiver} = option;
            setForm(draft => ({...draft,receiver,destination:{value:receiver.address,municipality}}));
          }}/>
        <label className={styles.adr}>Inleveransnummer<input value={form.deliveryNumber} maxLength={50}
          onChange={event => update('deliveryNumber',event.target.value)}/></label>
      </fieldset>
    </section>

    <section className="panel">
      <h2>Transportsträcka</h2>
      <div className={styles.split}>
        <LocationFields label="Hämtplats" location={form.origin} onChange={value => update('origin',value)} onMunicipality={setMunicipality('origin')}/>
        <LocationFields label="Slutlig mottagningsplats" location={form.destination} onChange={value => update('destination',value)}
          onMunicipality={setMunicipality('destination')}/>
      </div>
    </section>

    <section className="panel">
      <h2>Avfall som transporteras</h2>
      <p>Ange uppskattad eller invägd vikt för varje avfallsrad. Du kan fylla i båda om vikterna är kända.</p>
      {form.waste.map((row,index) => <WasteFields key={index} row={row} index={index} choices={codes}
        onChange={value => update('waste',form.waste.map((item,i) => i === index ? value : item))}
        onRemove={form.waste.length > 1 ? () => update('waste',form.waste.filter((_,i) => i !== index)) : undefined}/>)}
      <button type="button" className={`secondary ${styles.fit}`} disabled={form.waste.length >= 100}
        onClick={() => update('waste',[...form.waste,emptyWaste])}><Plus size={16}/> Lägg till avfallsrad</button>
      <label className={styles.adr}>Referens till separat ADR-handling, om tillämpligt
        <input value={form.adrReference} maxLength={70} onChange={event => update('adrReference',event.target.value)}/>
      </label>
    </section>

    <section className="panel">
      <h2>Underskrifter före avfärd</h2>
      <p>Skriv ut PDF:en och låt transportören och eventuell lämnare underteckna. Dokumentet ska följa med transporten.</p>
      <p>PDF:en har även en frivillig mottagningskvittens som fylls i vid lossning.</p>
      <div className={styles.grid}>
        <label>Transportörens namnförtydligande<input value={form.carrierSigner} maxLength={100}
          onChange={event => update('carrierSigner',event.target.value)}/></label>
        {form.consignor && <label>Lämnarens namnförtydligande<input value={form.consignorSigner} maxLength={100}
          onChange={event => update('consignorSigner',event.target.value)}/></label>}
      </div>
      {profileName && !form.carrierSigner && <button type="button" className={`secondary ${styles.fit}`}
        onClick={() => update('carrierSigner',profileName)}>Fyll i mitt namn som transportörens företrädare</button>}
    </section>

    <div className={styles.actions}>
      <button type="submit" disabled={exporting}><Download size={17}/> {exporting ? 'Skapar PDF…' : 'Ladda ner PDF för underskrift'}</button>
      {feedback && <span role={feedback.error ? 'alert' : 'status'}>{feedback.text}</span>}
    </div>
  </form>;
}
