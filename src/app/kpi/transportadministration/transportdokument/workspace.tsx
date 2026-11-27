'use client';

import {useRef, useState, type FormEvent, type PointerEvent} from 'react';
import {Download, Plus, Trash2} from 'lucide-react';
import {GoogleAddressField, geocodeSwedishAddress, reverseGeocodePoint, type Point} from '@/app/_components/google-address-field';
import {useGoogleMapsKey} from '@/app/_components/google-maps-provider';
import {customReceiver, emptyParty, emptySignoff, municipalityFor, municipalityOptions, receiverOptions, wasteOptions,
  type DocumentFields, type HubChoice, type Party, type Signoff, type StrokePoint, type Waste} from '@/lib/hub/transport-document/fields';
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
      <input value={value} maxLength={max} required onChange={event => {
        setSelection('');
        onChange(event.target.value);
      }}/>
    </label>
  </div>;
}

function PartyFields({party,onChange,onMunicipality}: {
  party: Party; onChange: (party: Party) => void; onMunicipality: (address: string, code: string) => void;
}) {
  const mapsKey = useGoogleMapsKey();
  const [place,setPlace] = useState<{address: string; id?: string; point?: Point}>();
  const [status,setStatus] = useState<{address: string; message: string; pending?: boolean}>();
  const sequence = useRef(0);
  const selected = place?.address === party.address ? place : undefined;

  async function lookup(address: string, point?: Point) {
    if (!mapsKey || !address.trim()) return;
    const request = ++sequence.current;
    setStatus({address,message:'Hämtar kommunkod…',pending:true});
    try {
      const results = point ? await reverseGeocodePoint(mapsKey,point) : await geocodeSwedishAddress(mapsKey,address);
      if (sequence.current !== request) return;
      const matches = results.filter(result => !result.partial_match && (point || result.types.some(type =>
        ['street_address','premise','subpremise','establishment','point_of_interest','postal_code','intersection'].includes(type))));
      const codes = [...new Set(matches.map(match => municipalityFor(match.address_components)).filter(Boolean))];
      if (codes.length === 1) {
        onMunicipality(address,codes[0]);
        setStatus({address,message:'Kommunkod hämtad från Google och SCB.'});
      } else {
        setStatus({address,message:'Välj ett exakt adressförslag eller välj kommun själv.'});
      }
    } catch {
      if (sequence.current === request) setStatus({address,message:'Kommunkoden kunde inte hämtas. Välj kommun i listan.'});
    }
  }

  return <div className={styles.grid}>
    <label>Företag<input required value={party.name} onChange={event => onChange({...party,name:event.target.value})} maxLength={80}/></label>
    <label>Organisationsnummer<input required value={party.organisation} onChange={event => onChange({...party,organisation:event.target.value})}
      placeholder="XXXXXX-XXXX" maxLength={18}/></label>
    <div className={styles.address}>
      <GoogleAddressField label="Postadress" value={party.address} placeId={selected?.id} point={selected?.point} autocomplete
        onChange={(address,id,point) => {
          sequence.current += 1;
          setStatus(undefined);
          setPlace({address,id,point});
          onChange({...party,address,municipality:address === party.address ? party.municipality : ''});
          if (point || id) void lookup(address,point);
        }}/>
      {mapsKey && <button type="button" className="secondary" disabled={!party.address.trim() || (status?.address === party.address && status.pending)}
        onClick={() => void lookup(party.address,selected?.point)}>Hämta kommunkod</button>}
      {status?.address === party.address && <small role="status">{status.message}</small>}
    </div>
    <label>Kommun
      <select value={party.municipality} required onChange={event => {
        sequence.current += 1;
        setStatus(undefined);
        onChange({...party,municipality:event.target.value});
      }}>
        <option value="">Välj kommun</option>
        {municipalityOptions.map(([code,name]) => <option value={code} key={code}>{name} ({code})</option>)}
      </select>
    </label>
  </div>;
}

function SignoffFields({label,value,onChange}: {label: string; value: Signoff; onChange: (value: Signoff) => void}) {
  const drawing = useRef<{id: number; box: DOMRect; completed: StrokePoint[][]; current: StrokePoint[]; count: number} | null>(null);

  function addPoint(event: PointerEvent<SVGSVGElement>) {
    const stroke = drawing.current;
    if (!stroke || stroke.id !== event.pointerId || stroke.count >= 3500) return;
    const {box} = stroke;
    const clamp = (n: number) => Math.round(Math.max(0,Math.min(1,n)) * 10_000) / 10_000;
    const point: StrokePoint = [clamp((event.clientX-box.left)/box.width),clamp((event.clientY-box.top)/box.height)];
    const previous = stroke.current.at(-1);
    if (previous?.[0] === point[0] && previous[1] === point[1]) return;
    stroke.current = [...stroke.current,point];
    stroke.count += 1;
    onChange({...value,strokes:[...stroke.completed,stroke.current]});
  }

  return <fieldset className={styles.signoff}>
    <legend>{label}</legend>
    <div className={styles.grid}>
      <label>Datum<input type="date" value={value.date} onChange={event => onChange({...value,date:event.target.value})}/></label>
      <label>Namnförtydligande<input maxLength={90} value={value.name} onChange={event => onChange({...value,name:event.target.value})}/></label>
    </div>
    <p>Rita underskriften här eller skriv under den utskrivna PDF:en.</p>
    <svg className={styles.signature} viewBox="0 0 500 100" preserveAspectRatio="none" role="img" aria-label={`Underskrift ${label.toLowerCase()}`}
      onPointerDown={event => {
        if (event.button !== 0 || drawing.current || value.strokes.length >= 80) return;
        const count = value.strokes.reduce((sum,line) => sum + line.length,0);
        if (count >= 3500) return;
        event.currentTarget.setPointerCapture(event.pointerId);
        drawing.current = {id:event.pointerId,box:event.currentTarget.getBoundingClientRect(),completed:value.strokes,current:[],count};
        addPoint(event);
      }}
      onPointerMove={addPoint}
      onLostPointerCapture={event => {
        if (drawing.current?.id === event.pointerId) drawing.current = null;
      }}>
      {value.strokes.map((stroke,index) => stroke.length === 1
        ? <circle key={index} cx={stroke[0][0]*500} cy={stroke[0][1]*100} r="1.25" fill="currentColor"/>
        : <polyline key={index} fill="none" stroke="currentColor" strokeWidth="2.5"
          strokeLinecap="round" strokeLinejoin="round" points={stroke.map(([x,y]) => `${x*500},${y*100}`).join(' ')}/>)}
    </svg>
    <button type="button" className="secondary" disabled={!value.strokes.length}
      onClick={() => onChange({...value,strokes:[]})}>Rensa underskrift</button>
  </fieldset>;
}

const packagingOptions = ['Flak','Container','Storsäck','Säck','Fat','Dunk','Pall','Löst'];

function WasteFields({entry,onChange,onRemove}: {entry: Waste; onChange: (entry: Waste) => void; onRemove: () => void}) {
  const [name,code] = wasteOptions[entry.row];
  const change = <K extends keyof Omit<Waste,'row'>>(field: K, value: Waste[K]) => onChange({...entry,[field]:value});
  return <fieldset className={styles.waste}>
    <legend>{name} <span className={styles.code}>{code}</span></legend>
    <div className={styles.grid}>
      <label>Antal kollin<input value={entry.packages} inputMode="numeric" maxLength={18}
        onChange={event => change('packages',event.target.value)}/></label>
      <label>Emballage<input list="transport-packaging" value={entry.packaging} maxLength={28}
        onChange={event => change('packaging',event.target.value)}/></label>
      <label>Uppskattad vikt (kg)<input inputMode="decimal" value={entry.estimatedKg} maxLength={18}
        onChange={event => change('estimatedKg',event.target.value)}/></label>
      <label>Invägd vikt (kg)<input inputMode="decimal" value={entry.weighedKg} maxLength={18}
        onChange={event => change('weighedKg',event.target.value)}/></label>
      <label>ADR<select value={entry.adr} onChange={event => change('adr',event.target.value as Waste['adr'])}>
        <option value="">Välj vid behov</option><option value="label">ADR-etikett</option><option value="none">Ej ADR</option>
      </select></label>
      {entry.adr === 'label' && <label>ADR-etikett<input required value={entry.adrLabel} maxLength={24}
        onChange={event => change('adrLabel',event.target.value)}/></label>}
    </div>
    <button type="button" className="secondary" onClick={onRemove} aria-label={`Ta bort ${name}`}><Trash2 size={15}/> Ta bort</button>
  </fieldset>;
}

export function DocumentWorkspace({projects,vehicles,profileName,today,failed}: {
  projects: HubChoice[]; vehicles: HubChoice[]; profileName: string; today: string; failed: boolean;
}) {
  const [form,setForm] = useState<DocumentFields>(() => ({
    createdBy:profileName,project:'',registration:'',
    sender:{...emptyParty,name:'Elleholms Maskin AB',organisation:'556863-2383'},
    receiver:emptyParty,receiverRow:-1,deliveryNumber:'',waste:[],
    senderSignoff:{...emptySignoff,date:today,name:profileName},receiverSignoff:emptySignoff,
  }));
  const [wasteChoice,setWasteChoice] = useState('');
  const [exporting,setExporting] = useState(false);
  const [feedback,setFeedback] = useState<{message: string; error?: boolean}>();
  const update = <K extends keyof DocumentFields>(key: K, value: DocumentFields[K]) =>
    setForm(draft => ({...draft,[key]:value}));
  const changeMunicipality = (party: 'sender' | 'receiver') => (address: string, code: string) => setForm(draft =>
    draft[party].address === address ? {...draft,[party]:{...draft[party],municipality:code}} : draft);

  function addWaste() {
    if (!wasteChoice) return;
    const row = Number(wasteChoice);
    const entry: Waste = {row,packages:'',packaging:'',estimatedKg:'',weighedKg:'',adr:'',adrLabel:''};
    setForm(draft => draft.waste.some(item => item.row === row) ? draft :
      {...draft,waste:[...draft.waste,entry].sort((a,b) => a.row-b.row)});
    setWasteChoice('');
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
      link.download = `Transportdokument-${form.project.trim().replace(/[^\p{L}\p{N}_-]+/gu,'-')}.pdf`;
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url),30_000);
      setFeedback({message:'PDF:en har skapats.'});
    } catch (error) {
      setFeedback({error:true,message:error instanceof Error ? error.message : 'PDF:en kunde inte skapas.'});
    } finally {
      setExporting(false);
    }
  }

  const selectedReceiver = receiverOptions[form.receiverRow];
  return <form className={`content ${styles.form}`} onSubmit={download}>
    <section className="panel">
      <h2>Projekt och avsändare</h2>
      {failed && <p role="status">Alla projekt eller fordon kunde inte hämtas från Humla. Du kan fylla i dem manuellt.</p>}
      <div className={styles.grid}>
        <HubField label="Projektnummer" max={28} value={form.project} options={projects} onChange={value => update('project',value)}
          onSelect={choice => update('project',choice.value)}/>
        <HubField label="Registreringsnummer" max={24} value={form.registration} options={vehicles}
          onChange={value => update('registration',value)} onSelect={choice => update('registration',choice.value)}/>
        <label>Dokument skapat av<input required maxLength={90} value={form.createdBy}
          onChange={event => update('createdBy',event.target.value)}/></label>
      </div>
      <PartyFields party={form.sender} onChange={value => update('sender',value)} onMunicipality={changeMunicipality('sender')}/>
    </section>

    <section className="panel">
      <h2>Mottagare</h2>
      <div className={styles.grid}>
        <label>Mottagningsanläggning
          <select value={form.receiverRow < 0 ? '' : form.receiverRow} required onChange={event => {
            const row = event.target.value ? Number(event.target.value) : -1;
            setForm(draft => ({...draft,receiverRow:row,deliveryNumber:'',receiver:receiverOptions[row] ?? emptyParty}));
          }}>
            <option value="">Välj mottagare</option>
            {receiverOptions.map((option,index) => <option key={option.name} value={index}>{option.name}</option>)}
            <option value={customReceiver}>Annan mottagare</option>
          </select>
        </label>
        <label>Inleveransnummer<input maxLength={30} value={form.deliveryNumber}
          onChange={event => update('deliveryNumber',event.target.value)}/></label>
      </div>
      {selectedReceiver && <dl className={styles.receiver}>
        <div><dt>Postadress</dt><dd>{selectedReceiver.address}</dd></div>
        <div><dt>Organisationsnummer</dt><dd>{selectedReceiver.organisation}</dd></div>
        <div><dt>Kommunkod</dt><dd>{selectedReceiver.municipality}</dd></div>
      </dl>}
      {form.receiverRow === customReceiver && <PartyFields party={form.receiver} onChange={value => update('receiver',value)}
        onMunicipality={changeMunicipality('receiver')}/>}
    </section>

    <section className="panel">
      <h2>Avfall</h2>
      <div className={styles.addRow}>
        <label>Avfallsslag
          <select value={wasteChoice} onChange={event => setWasteChoice(event.target.value)}>
            <option value="">Välj avfallsslag</option>
            {wasteOptions.map(([name,code],index) => <option key={name} value={index}
              disabled={form.waste.some(entry => entry.row === index)}>{name} ({code})</option>)}
          </select>
        </label>
        <button type="button" className="secondary" onClick={addWaste} disabled={!wasteChoice}><Plus size={16}/> Lägg till</button>
      </div>
      <datalist id="transport-packaging">{packagingOptions.map(option => <option value={option} key={option}/>)}</datalist>
      {form.waste.map(entry => <WasteFields key={entry.row} entry={entry}
        onChange={value => setForm(draft => ({...draft,waste:draft.waste.map(item => item.row === entry.row ? value : item)}))}
        onRemove={() => setForm(draft => ({...draft,waste:draft.waste.filter(item => item.row !== entry.row)}))}/>)}
    </section>

    <section className="panel">
      <h2>Underskrifter</h2>
      <div className={styles.signoffs}>
        <SignoffFields label="Lämnare" value={form.senderSignoff} onChange={value => update('senderSignoff',value)}/>
        <SignoffFields label="Mottagare" value={form.receiverSignoff} onChange={value => update('receiverSignoff',value)}/>
      </div>
    </section>

    <div className={styles.actions}>
      <button type="submit" disabled={exporting}><Download size={17}/> {exporting ? 'Skapar PDF…' : 'Ladda ner PDF'}</button>
      {feedback && <span role={feedback.error ? 'alert' : 'status'}>{feedback.message}</span>}
    </div>
  </form>;
}
