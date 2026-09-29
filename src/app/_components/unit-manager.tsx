"use client";
import {useState} from 'react';
import type {KpiUnit,UnitReport} from '@/lib/kpi/units';
const money = new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
const unitTypes = {vehicle:'Fordon/ekipage',person:'Person',overhead:'Övergripande kostnader'};
export function UnitManager({units,report,canManage,from}:{units:KpiUnit[];report:UnitReport;canManage:boolean;from:string}) {
 const [editing,setEditing]=useState<KpiUnit|null>(null),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
 const [formKey,setFormKey]=useState(0);
 async function save(form:FormData) {
  setBusy(true);setMessage('');
  try {
   const body={...Object.fromEntries(form),enabled:form.get('enabled')==='on',id:editing?.id,revision:editing?.revision};
   const response=await fetch('/api/kpi/units',{method:editing?'PATCH':'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});
   const result=await response.json();
   if(!response.ok) throw new Error(result.error);
   window.location.reload();
  } catch(error) {setMessage(error instanceof Error?error.message:'Kunde inte spara. Ladda om och kontrollera innan nytt försök.');}
  finally {setBusy(false);}
 }
 function edit(unit:KpiUnit|null) {setEditing(unit);setFormKey(v=>v+1);}
 return <div className="account-layout">
  <section className="panel"><h2>Enheter – bil, släp och person tillsammans</h2><p>Skapa exempelvis enheten ABC123 och koppla flera projekt, regnummer och anställningsnummer. En rad som träffar flera kopplingar till samma enhet räknas bara en gång. Träffar den olika enheter hålls den utanför enhetsresultatet.</p><p>Personreferenserna gäller importerade anställningsnummer. Ingen permanent personidentitet skapas i Hub och ingen lönekostnad beräknas automatiskt från timmar.</p><p>Kontoregler gäller för samtliga typer. ”Ta med i fordonsresultat” styr fordonsenheter; övergripande kostnader kan följas separat även när de inte ska belasta ett fordon. Översiktens ordinarie KPI:er ändras inte av grupperingen.</p></section>
  <section className="panel"><h2>Uppföljning för vald period</h2><p>{report.quality.conflicts??0} rader med motstridiga enheter · {report.quality.unassigned??0} utan enhet · {report.quality.invalid??0} ogiltiga · {report.quality.unmapped_accounts??0} utan kontoregel. Antalen kan överlappa.</p><div className="table-wrap"><table><thead><tr><th>Enhet</th><th>Intäkt</th><th>Kostnad</th><th>Bränsle</th><th>Resultat</th><th>Betald tid</th><th>Debiterbar tid</th><th>Rader</th></tr></thead><tbody>{units.map(unit=>{
   const total=report.units.find(item=>item.unit_id===unit.id);
   return <tr key={unit.id}><td><details><summary>{unit.name} · {unitTypes[unit.unit_type]}{!unit.enabled?' (avstängd)':''}</summary><p>Projekt: {unit.projects.join(', ')||'–'}</p><p>Regnummer: {unit.registrations.join(', ')||'–'}</p><p>Anställningsnummer: {unit.employees.join(', ')||'–'}</p><p>{unit.valid_from} – {unit.valid_to??'tills vidare'}</p>{canManage&&<button className="secondary" onClick={()=>edit(unit)}>Redigera kopplingar</button>}</details></td><td>{money.format(total?.revenue??0)}</td><td>{money.format(total?.cost??0)}</td><td>{money.format(total?.fuel??0)}</td><td>{money.format(total?.result??0)}</td><td>{total?.paid_hours??0} h</td><td>{total?.billable_hours??0} h</td><td>{total?.row_count??0}</td></tr>;
  })}</tbody></table></div>{!units.length&&<p>Inga enheter ännu. Skapa den första nedan.</p>}
  {!!report.conflict_rows.length&&<details><summary>Visa konflikter (högst 50 rader)</summary><ul>{report.conflict_rows.map(row=><li key={row.batch_id+':'+row.row_number}>Import {row.batch_id}, datarad {row.row_number}: projekt {row.project_reference||'–'}, fordon {row.vehicle_registration||'–'}, person {row.employee_number||'–'}</li>)}</ul></details>}</section>
  {canManage&&<section className="panel"><h2>{editing?'Redigera enhet':'Ny enhet'}</h2><p>Ange en referens per rad. Matchning sker exakt inom denna KPI-arbetsyta. Giltighetsdatumen avgör vilka transaktioner som omfattas. En ändring räknar om tidigare perioder inom intervallet och loggas.</p><form key={formKey} action={save} className="account-form"><fieldset disabled={busy} style={{display:'contents'}}>
   <label>Typ av uppföljning<select name="unit_type" defaultValue={editing?.unit_type??'overhead'}>{Object.entries(unitTypes).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label>
   <p className="wide">NEXT-projekt skapar inga fordon. Gemensamma kostnader följs separat under Övergripande kostnader och fördelas inte automatiskt på fordonsenheter.</p>
   <label className="wide">Enhetsnamn<input name="name" required maxLength={120} defaultValue={editing?.name??''} placeholder="Ex. ABC123"/></label>
   <label>Projekt<textarea name="projects" rows={5} defaultValue={editing?.projects.join('\n')??''} placeholder="Ett projektnummer per rad"/></label>
   <label>Bil och släp<textarea name="registrations" rows={5} defaultValue={editing?.registrations.join('\n')??''} placeholder="Ett regnummer per rad"/></label>
   <label>Anställningsnummer<textarea name="employees" rows={5} defaultValue={editing?.employees.join('\n')??''} placeholder="Ett anställningsnummer per rad"/></label>
   <label>Gäller från<input type="date" name="valid_from" required defaultValue={editing?.valid_from??from}/></label><label>Gäller till<input type="date" name="valid_to" defaultValue={editing?.valid_to??''}/></label>
   <label className="check-line"><input type="checkbox" name="enabled" defaultChecked={editing?.enabled??true}/>Aktiv</label>
   <div className="wide form-actions"><button className="primary">{busy?'Sparar…':'Spara enhet'}</button>{editing&&<button className="secondary" type="button" onClick={()=>edit(null)}>Avbryt redigering</button>}</div>
  </fieldset></form>{message&&<p role="alert">{message}</p>}</section>}
 </div>;
}
