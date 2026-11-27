'use client';

import {useRef, useState, type FormEvent} from 'react';
import {Download, Plus, Trash2} from 'lucide-react';
import {GoogleAddressField, geocodeSwedishAddress, reverseGeocodePoint, type Point} from '@/app/_components/google-address-field';
import {useGoogleMapsKey} from '@/app/_components/google-maps-provider';
import {elleholms, emptyParty, emptyLocation, emptyWaste, municipalityFor, municipalityOptions, receiverOptions,
  type DocumentFields, type HubChoice, type Location, type Party, type Waste} from '@/lib/hub/transport-document/fields';
import {suggestedWaste, wasteCodeAt} from '@/lib/hub/transport-document/waste-codes';
import styles from './workspace.module.css';

function HubField({label,options,value,onChange,onSelect,max}: {
  label: string; options: HubChoice[]; value: string; onChange: (value: string) => void;
  onSelect: (option: HubChoice) => void; max: number;
}) {
  const [selection,setSelection] = useState('');
  return <div className={styles.stack}>
    {options.length > 0 && <label>{label} från Humla
      <select value={selection} onChange={event => {
        const id = event.target.value;
        setSelection(id);
        const choice = options.find(option => option.id === id);
        if (choice) onSelect(choice);
      }}>
        <option value="">Välj eller fyll i manuellt</option>
        {options.map(option => <option key={option.id} value={option.id}>{option.label}</option>)}
      </select>
    </label>}
    <label>{label}
      <input value={value} maxLength={max} onChange={event => {
        setSelection('');
        onChange(event.target.value);
      }}/>
    </label>
  </div>;
}

function PartyFields({party,onChange}: {party: Party; onChange: (party: Party) => void}) {
  return <div className={styles.grid}>
    <label>Namn eller företagsnamn<input value={party.name} maxLength={110} required
      onChange={event => onChange({...party,name:event.target.value})}/></label>
    <label>Organisations-, person- eller skatteregistreringsnummer<input value={party.organisation} maxLength={30} required
      onChange={event => onChange({...party,organisation:event.target.value})}/></label>
    <label>Postadress<input value={party.address} maxLength={220} required
      onChange={event => onChange({...party,address:event.target.value})}/></label>
  </div>;
}

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
    <label>Kommun
      <select value={location.municipality} onChange={event => {
        sequence.current += 1;
        setStatus(undefined);
        onChange({...location,municipality:event.target.value});
      }}>
        <option value="">Välj kommun vid behov</option>
        {municipalityOptions.map(([code,name]) => <option key={code} value={code}>{name} ({code})</option>)}
      </select>
    </label>
  </fieldset>;
}

const packagingOptions = ['Flak','Container','Storsäck','Säck','Fat','Dunk','Pall','Löst'];

function WasteFields({row,index,date,onChange,onRemove}: {row: Waste; index: number; date: string; onChange: (row: Waste) => void; onRemove?: () => void}) {
  const validated = date && wasteCodeAt(row.code,date);
  return <fieldset className={styles.fieldset}>
    <legend>Avfallsrad {index+1}</legend>
    <div className={styles.grid}>
      <label>Avfallskod<input value={row.code} maxLength={15} list="transport-waste-codes" required
        onChange={event => {
          const code = event.target.value;
          const suggestion = suggestedWaste.find(([key]) => key === code);
          const previousSuggestion = suggestedWaste.find(([key]) => key === row.code);
          const useSuggestion = !row.name || row.name === previousSuggestion?.[1];
          onChange({...row,code,name:useSuggestion ? suggestion?.[1] ?? '' : row.name});
        }}/>
        {row.code && date && !validated && <small>Kontrollera koden mot avfallsförteckningen för transportdatumet.</small>}
      </label>
      <label>Benämning<input value={row.name} maxLength={180} required onChange={event => onChange({...row,name:event.target.value})}/></label>
      <label>Uppskattad vikt (kg)<input value={row.estimatedKg} inputMode="decimal" maxLength={18}
        onChange={event => onChange({...row,estimatedKg:event.target.value})}/></label>
      <label>Invägt kg<input value={row.weighedKg} inputMode="decimal" maxLength={18}
        onChange={event => onChange({...row,weighedKg:event.target.value})}/></label>
      <label>Antal kollin<input value={row.packages} inputMode="numeric" maxLength={10} onChange={event => onChange({...row,packages:event.target.value})}/></label>
      <label>Emballage<input value={row.packaging} list="transport-packaging" maxLength={45} onChange={event => onChange({...row,packaging:event.target.value})}/></label>
    </div>
    {onRemove && <button type="button" className="secondary" onClick={onRemove} aria-label={`Ta bort avfallsrad ${index+1}`}>
      <Trash2 size={15}/> Ta bort
    </button>}
  </fieldset>;
}

export function DocumentWorkspace({projects,vehicles,profileName,today,failed}: {
  projects: HubChoice[]; vehicles: HubChoice[]; profileName: string; today: string; failed: boolean;
}) {
  const [form,setForm] = useState<DocumentFields>(() => ({
    date:today,project:'',registration:'',carrier:elleholms,consignor:emptyParty,receiver:emptyParty,
    origin:emptyLocation,destination:emptyLocation,deliveryNumber:'',adrReference:'',waste:[emptyWaste],
    carrierSigner:'',consignorSigner:'',
  }));
  const [receiverId,setReceiverId] = useState('');
  const [exporting,setExporting] = useState(false);
  const [feedback,setFeedback] = useState<{text: string; error?: boolean}>();
  const lastConsignor = useRef<Party>(emptyParty);
  const update = <K extends keyof DocumentFields>(key: K, value: DocumentFields[K]) =>
    setForm(draft => ({...draft,[key]:value}));
  const setMunicipality = (field: 'origin' | 'destination') => (value: string, code: string) => setForm(draft =>
    draft[field].value === value ? {...draft,[field]:{value,municipality:code}} : draft);

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
      {failed && <p role="status">Alla projekt eller fordon kunde inte hämtas från Humla. Du kan fylla i dem manuellt.</p>}
      <div className={styles.grid}>
        <label>Transportdatum<input type="date" value={form.date} required onChange={event => update('date',event.target.value)}/></label>
        <HubField label="Projekt" max={95} value={form.project} options={projects} onChange={value => update('project',value)}
          onSelect={choice => update('project',choice.value)}/>
        <HubField label="Registreringsnummer" max={24} value={form.registration} options={vehicles}
          onChange={value => update('registration',value)} onSelect={choice => update('registration',choice.value)}/>
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
          if (form.consignor) lastConsignor.current = form.consignor;
          update('consignor',event.target.checked ? null : lastConsignor.current);
        }}/> Ingen separat lämnare, till exempel vid egen transport av eget avfall</label>
        {form.consignor && <PartyFields party={form.consignor} onChange={value => update('consignor',value)}/>}
      </fieldset>
      <fieldset className={styles.fieldset}>
        <legend>Slutlig mottagare</legend>
        <div className={styles.grid}>
          <label>Välj mottagare
            <select value={receiverId} onChange={event => {
              const id = event.target.value;
              setReceiverId(id);
              const option = id === '' ? undefined : receiverOptions[Number(id)];
              if (option) {
                const {municipality,...receiver} = option;
                setForm(draft => ({...draft,receiver,destination:{value:receiver.address,municipality}}));
              }
            }}>
              <option value="">Fyll i mottagaren själv</option>
              {receiverOptions.map((option,index) => <option key={option.name} value={index}>{option.name}</option>)}
            </select>
          </label>
          <label>Inleveransnummer<input value={form.deliveryNumber} maxLength={50} onChange={event => update('deliveryNumber',event.target.value)}/></label>
        </div>
        <PartyFields party={form.receiver} onChange={value => {setReceiverId('');update('receiver',value);}}/>
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
      <datalist id="transport-packaging">{packagingOptions.map(option => <option value={option} key={option}/>)}</datalist>
      <datalist id="transport-waste-codes">{suggestedWaste.map(([code,name]) => <option value={code} key={code}>{name}</option>)}</datalist>
      {form.waste.map((row,index) => <WasteFields key={index} row={row} index={index} date={form.date}
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
