'use client';

import {useEffect,useRef,useState} from 'react';
import {geocodeSwedishAddress} from '@/app/_components/google-address-field';
import {useGoogleMapsKey} from '@/app/_components/google-maps-provider';
import {yardAddressKey,yardAddressQueries,type AddressSide,type YardAddressClue,type YardAddressQuery} from '@/lib/hub/sortergard-address-clues';
import {loadYardAddressClues,saveLikelyYardAddress} from './actions';
import type {Candidate} from '@/lib/hub/sortergard-report';

const nearby = {south:55.83,west:13.73,north:56.56,east:16.08};
type Match = {address:string; note:string; hint:YardAddressQuery; score:number};

export function searchYardAddress(key:string,query:string) {
  return geocodeSwedishAddress(key,query,nearby);
}
type AddressSearch = (query:string)=>ReturnType<typeof searchYardAddress>;

async function findAddresses(search:AddressSearch,hint:YardAddressQuery):Promise<Match[]> {
  const results=await search(hint.query);
  const matches:Match[]=[];
  for(const result of results) {
    const component=(type:string)=>result.address_components.find(item=>item.types.includes(type))?.long_name;
    const route=component('route');
    if(hint.street&&(!route||yardAddressKey(hint.street)!==yardAddressKey(route))) continue;
    if(hint.postcode&&yardAddressKey(component('postal_code')??'')!==yardAddressKey(hint.postcode)) continue;
    const point=result.geometry.location.toJSON();
    if(!hint.postcode&&!hint.locality&&(point.lat<nearby.south||point.lat>nearby.north||point.lng<nearby.west||point.lng>nearby.east)) continue;
    if(!route&&!result.types.some(type=>['premise','subpremise','point_of_interest','establishment','plus_code'].includes(type))) continue;
    const number=component('street_number');
    const numberMatches=hint.number&&number&&yardAddressKey(number)===yardAddressKey(hint.number);
    const localityMatches = !hint.locality || result.address_components.some(item =>
      yardAddressKey(item.long_name)===yardAddressKey(hint.locality??''));
    const note=result.partial_match||(hint.number&&!numberMatches)||!localityMatches ? 'Kontrollera träffen'
      : route&&!hint.number ? 'Gata. Gatunummer saknas i underlaget.' : 'Adressförslag';
    const confirmed = !result.partial_match && (!hint.number || numberMatches) && localityMatches;
    const score = confirmed
      ? hint.clue.address && hint.number ? 92 : hint.number && (hint.postcode || hint.locality) ? 84
        : hint.number ? 72 : hint.locality ? 67 : 56
      : 50;
    matches.push({address:result.formatted_address,note,hint,score});
  }
  return matches.slice(0,3);
}

function clueLabel(clue:YardAddressClue) {
  return [clue.source,clue.reference,clue.reason].filter(Boolean).join(' · ');
}

export async function assessYardAddress(year:number,event:string,kind:string,mapsKey:string|null) {
  const result=await loadYardAddressClues(year,event);
  if(result.error||!result.clues) throw new Error(result.error??'Adressunderlaget kunde inte hämtas.');
  const clues=result.clues;
  const checks=await inspectYardAddresses(clues,kind,mapsKey ? query=>searchYardAddress(mapsKey,query) : undefined);
  const {hints,matches,preferred,googleFailed}=checks;
  const applied=preferred&&(kind==='Inleverans'||kind==='Utleverans')
    ? await saveLikelyYardAddress(year,event,preferred):undefined;
  if(applied?.error) throw new Error(applied.error);
  const message=applied?.saved? `Adressen används i årsrapporten som sannolik (${preferred?.score} av 100).`
    : !hints.length?'Ingen gata eller arbetsplatsadress kunde tolkas från underlaget.'
    : !mapsKey?'Google Maps är inte tillgängligt i den här vyn.'
    : googleFailed?(matches.length?'En del Google-sökningar kunde inte slutföras.':'Google kunde inte slutföra adressökningen.')
    : !matches.length?'Google hittade ingen matchande plats för sökunderlaget.'
    : !preferred?'Flera möjliga adresser eller för svagt underlag. Granska träffarna nedan.':'';
  return {clues,hints,matches,message,saved:applied?.saved&&preferred};
}

export async function inspectYardAddresses(clues:YardAddressClue[],kind:string,search?:AddressSearch) {
  const hints=yardAddressQueries(clues).filter(hint=>
    !(kind==='Inleverans'&&hint.side==='destination')&&!(kind==='Utleverans'&&hint.side==='origin'));
  const responses=search ? await Promise.allSettled(hints.map(hint=>findAddresses(search,hint))) : [];
  const unique=new Map<string,Match>();
  for(const response of responses) if(response.status==='fulfilled') {
    for(const match of response.value) {
      const matchKey=yardAddressKey(match.address)+'|'+(match.hint.side??'');
      if((unique.get(matchKey)?.score??0)<match.score) unique.set(matchKey,match);
    }
  }
  const matches=[...unique.values()].sort((a,b)=>b.score-a.score);
  const aak=clues.find(clue=>clue.source==='AAK');
  const candidates:Candidate[]=matches.filter(match=>match.hint.clue.source!=='AAK').map(match=>({
    address:match.hint.query,source:match.hint.clue.source,reference:match.hint.clue.reference,
    score:match.score,reason:'Adressuppgift kontrollerad mot Google Maps',
  }));
  if(aak?.address) candidates.push({address:aak.address,source:'AAK',reference:aak.reference,score:78,reason:aak.reason});
  candidates.sort((a,b)=>b.score-a.score);
  const top=candidates[0];
  const rival=candidates.find(candidate=>top&&yardAddressKey(candidate.address)!==yardAddressKey(top.address));
  // Different Google results for the same abbreviated input also indicate ambiguity.
  const ambiguous=top&&top.source!=='AAK'&&matches
    .filter(match=>match.score>=top.score-8&&yardAddressKey(match.hint.query)===yardAddressKey(top.address)).length>1;
  const preferred=top&&top.score>50&&!ambiguous&&(!rival||top.score-rival.score>=9||(top.source==='AAK'&&rival.score<78))?top:undefined;
  return {hints,matches,preferred,googleFailed:responses.some(response=>response.status==='rejected')};

}

export default function YardAddressAssist({year,event,kind,apply,onSaved}:{
  year:number;event:string;kind:string;apply:(side:AddressSide,address:string)=>void;onSaved:()=>void;
}) {
  const mapsKey=useGoogleMapsKey();
  const mounted=useRef(false);
  useEffect(()=>{
    mounted.current=true;
    return ()=>{mounted.current=false;};
  },[]);
  const [busy,setBusy]=useState(false);
  const [message,setMessage]=useState('');
  const [clues,setClues]=useState<YardAddressClue[]>();
  const [queries,setQueries]=useState<YardAddressQuery[]>([]);
  const [matches,setMatches]=useState<Match[]>([]);
  async function search() {
    setBusy(true);setMessage('');setClues(undefined);setQueries([]);setMatches([]);
    try {
      const result=await assessYardAddress(year,event,kind,mapsKey);
      setClues(result.clues);setQueries(result.hints);setMatches(result.matches);setMessage(result.message);
      if(result.saved&&mounted.current) {
        apply(kind==='Inleverans'?'origin':'destination',result.saved.address);
        onSaved();
      }
    } catch(error) {setMessage(error instanceof Error?error.message:'Adressökningen kunde inte slutföras.');}
    finally {setBusy(false);}
  }
  return <section aria-label="Adressförslag">
    <button type="button" disabled={busy} onClick={()=>void search()}>{busy?'Söker adresser …':'Bedöm adress med Google'}</button>
    {message&&<p role="status">{message}</p>}
    {matches.length>0&&<div className="panel">
      <h4>Adressförslag från Google Maps</h4>
      <ul>{matches.map(({address,note,hint,score})=><li key={address+'|'+(hint.side??'')}>
        <strong>{address}</strong> · {note} · {score}/100
        <small> · {clueLabel(hint.clue)} · Sökning på {hint.query}</small>
      </li>)}</ul>
    </div>}
    {queries.length>0&&<details open>
      <summary>Tolkat sökunderlag</summary>
      <ul>{queries.map((hint,index)=><li key={index}>
        <strong>{hint.query}</strong> · {clueLabel(hint.clue)}{' '}
        {kind!=='Utleverans'&&hint.side!=='destination'&&<button type="button" onClick={()=>apply('origin',hint.query)}>Fyll i ursprungsadress</button>}{' '}
        {kind!=='Inleverans'&&hint.side!=='origin'&&<button type="button" onClick={()=>apply('destination',hint.query)}>Fyll i leveransadress</button>}
      </li>)}</ul>
    </details>}
    {clues&&<details>
      <summary>Underlag från Flintab, Next och Workify</summary>
      {clues.length?<ul>{clues.map((clue,index)=><li key={index}>{clueLabel(clue)} · {[clue.name,clue.address].filter(Boolean).join(' · ')}</li>)}</ul>
        :<p>Inga uppgifter i de matchade källorna.</p>}
    </details>}
  </section>;
}
