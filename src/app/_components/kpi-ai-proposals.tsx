'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
export type AiProposal={id:string;reference_key:string;targets:Record<string,string>;reason:string;confidence:number;status:string};
export function useKpiAiProposals(query:string,ready:boolean){
 const [proposals,setProposals]=useState<Record<string,AiProposal>>({}),[running,setRunning]=useState(false),[message,setMessage]=useState('');
 const control=useRef<AbortController|null>(null),started=useRef(''),cursor=useRef(0);
 const run=useCallback(async()=>{if(control.current)return;const c=new AbortController();control.current=c;setRunning(true);setMessage('Hubben tar fram förslag för alla rader i urvalet…');try{
 let page=cursor.current;
 while(!c.signal.aborted){const r=await fetch('/api/kpi/matching/suggestions',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({action:'generate',query,page}),signal:c.signal});const j=await r.json();if(!r.ok)throw Error(j.error);setProposals(s=>({...s,...Object.fromEntries((j.proposals as AiProposal[]).map(p=>[p.reference_key,p]))}));setMessage('Förslag sparade · sida '+(page+1)+' av '+Math.max(1,Math.ceil(j.total_groups/100)));if(j.next_page===null){setMessage('Alla rader i urvalet har bedömts. Godkänn förslagen direkt på raden.');cursor.current=0;break}page=j.next_page;cursor.current=page;
 }
 }catch(e){if(!c.signal.aborted)setMessage(e instanceof Error?e.message:'Förslagen kunde inte hämtas')}finally{if(control.current===c){control.current=null;setRunning(false)}}},[query]);
 const pause=useCallback(()=>{control.current?.abort();control.current=null;setRunning(false);setMessage('Pausat. Sparade förslag finns kvar.')},[]);
 useEffect(()=>{pause();cursor.current=0;setProposals({});started.current='';return()=>{control.current?.abort();control.current=null}},[query,pause]);
 useEffect(()=>{if(ready&&started.current!==query){started.current=query;void run()}},[ready,query,run]);
 async function resolve(p:AiProposal,action:'approve'|'reject'){pause();const r=await fetch('/api/kpi/matching/suggestions',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({action,id:p.id}),signal:AbortSignal.timeout(110000)});const j=await r.json();if(!r.ok)throw Error(j.error);setProposals(s=>({...s,[p.reference_key]:{...p,status:action==='approve'?'approved':'rejected'}}));return j;}
 return {proposals,running,message,run,pause,resolve};
}
export function KpiAiRow({proposal,disabled,onResolve,onEdit,label}:{proposal?:AiProposal;disabled:boolean;onResolve:(p:AiProposal,a:'approve'|'reject')=>void;onEdit:()=>void;label:(d:string,v:string)=>string}){
 if(!proposal)return <p><small>AI-förslag väntar på bedömning.</small></p>;
 return <aside aria-label="AI-förslag" style={{padding:'12px',marginTop:'10px',background:'#f3f7f6',borderRadius:'8px',maxWidth:'520px'}}><strong>{proposal.status==='approved'?'Godkänd och sparad':proposal.status==='rejected'?'Avvisat förslag':proposal.status==='needs_input'?'Underlag behöver kompletteras':'AI-förslag'}</strong>{Object.keys(proposal.targets).length>0&&<ul>{Object.entries(proposal.targets).map(([d,v])=><li key={d}>{label(d,v)}</li>)}</ul>}<p>{proposal.reason}</p><small>AI:s säkerhetsbedömning: {Math.round(Number(proposal.confidence)*100)} %</small>{proposal.status==='pending'&&<div style={{display:'flex',gap:'8px',flexWrap:'wrap',marginTop:'10px'}}><button type="button" className="primary" disabled={disabled} onClick={()=>onResolve(proposal,'approve')}>Godkänn</button><button type="button" disabled={disabled} onClick={onEdit}>Ändra här</button><button type="button" disabled={disabled} onClick={()=>onResolve(proposal,'reject')}>Avvisa</button></div>}{proposal.status==='needs_input'&&<div><button type="button" disabled={disabled} onClick={onEdit}>Komplettera här</button></div>}</aside>;
}
