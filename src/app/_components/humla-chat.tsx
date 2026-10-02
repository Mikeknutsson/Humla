'use client';
import Link from 'next/link';
import {useEffect,useRef,useState} from 'react';
import {Send,MessageSquare,Search,Trash2,ExternalLink} from 'lucide-react';
import styles from './humla-chat.module.css';
type Source={key:string;title:string;href:string;date:string;details:Record<string,unknown>};
type Message={role:'user'|'assistant';content:string;sources?:Source[];searchedAt?:string};
const examples=['Vad fakturerade vi Linnestofta Maskin för IFA aska sist?','Vilken är senaste mätarställningen på DFC86A?','Vad blev resultatet för Transport och Sortergården i september 2025?'];
function answerParts(m:Message){return m.content.split(/(\*\*[^*]+\*\*|\[K\d+\])/g).map((part,i)=>{if(part.startsWith('**')&&part.endsWith('**'))return <strong key={i}>{part.slice(2,-2)}</strong>;const source=m.sources?.find(s=>`[${s.key}]`===part);return source?<Link key={i} href={source.href} target="_blank" rel="noopener noreferrer" prefetch={false}>{part}</Link>:part;});}
export function HumlaChat(){
 const [messages,setMessages]=useState<Message[]>([]),[question,setQuestion]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');const end=useRef<HTMLDivElement>(null);const controller=useRef<AbortController|null>(null);
 useEffect(()=>()=>controller.current?.abort(),[]);
 useEffect(()=>{end.current?.scrollIntoView({behavior:'smooth',block:'end'});},[messages,busy]);
 async function send(value=question){const text=value.trim();if(!text||busy)return;const previous=messages.slice(-14);const next:Message[]=[...previous,{role:'user',content:text}];setMessages(next);setQuestion('');setError('');setBusy(true);controller.current=new AbortController();
 try{const res=await fetch('/api/ai/chat',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({messages:next.map(({role,content})=>({role,content}))}),signal:controller.current.signal});const body=await res.json();if(!res.ok)throw Error(body.error??'Frågan kunde inte besvaras.');setMessages([...next,{role:'assistant',content:body.answer,sources:body.sources,searchedAt:body.searchedAt}]);}catch(e){setError(e instanceof Error?e.message:'Frågan kunde inte besvaras.');setMessages(previous);setQuestion(text);}finally{setBusy(false);}}
 return <div className={styles.page}><header className={styles.header}><MessageSquare size={28}/><div><h1>Fråga Humla</h1><p>Sök i Hubben och följ underlagen hela vägen.</p></div><button disabled={busy||!messages.length} onClick={()=>{setMessages([]);setError('');setQuestion('');}}><Trash2 size={16}/>Nytt samtal</button></header>
 <div className={styles.coverage}><strong>Dina verksamhetsunderlag</strong><p>Chatten söker giltiga KPI-importer och verksamhetsobjekt, bland annat order, fordon, tankningar och mätningar. Den söker hela tillgängliga historiken om du inte anger en period. Dokument som inte har importerats och råa integrationsmeddelanden ingår inte.</p><p>Frågor och relevanta sökträffar behandlas av AI-tjänsten. Chatten kan läsa underlag; dina kopplingar och belopp ändras inte.</p></div>
 <div className={styles.conversation} aria-live="polite" aria-busy={busy}>
 {!messages.length&&<section className={styles.examples}><h2>Vad vill du veta?</h2>{examples.map(q=><button key={q} disabled={busy} onClick={()=>send(q)}><Search size={17}/>{q}</button>)}</section>}
 {messages.map((m,i)=><article key={i} className={m.role==='user'?styles.user:styles.assistant}><strong>{m.role==='user'?'Du':'Humla'}</strong><p className={styles.answer}>{answerParts(m)}</p>{m.sources?.length? <div className={styles.sources}><h3>Underlag bakom svaret</h3>{m.sources.map(s=><Link href={s.href} target="_blank" rel="noopener noreferrer" prefetch={false} key={s.key}><span>[{s.key}] {s.title}</span><small>{s.date} <ExternalLink size={13}/></small></Link>)}</div>:null}{m.searchedAt&&<small>Sökt {new Date(m.searchedAt).toLocaleString('sv-SE',{timeZone:'Europe/Stockholm'})} · Kontrollera underlaget vid beslut.</small>}</article>)}
 {busy&&<div className={styles.pending} role="status"><Search size={18}/>Söker i Hubben och kontrollerar underlagen…</div>}<div ref={end}/></div>
 {error&&<p className={styles.error} role="alert">{error}</p>}
 <form className={styles.composer} onSubmit={e=>{e.preventDefault();void send();}}><label htmlFor="humla-question">Din fråga</label><textarea id="humla-question" value={question} maxLength={4000} rows={2} disabled={busy} placeholder="Vad tog vi per ton för IFA aska senast?" onChange={e=>setQuestion(e.target.value)} onKeyDown={e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.nativeEvent.isComposing){e.preventDefault();void send();}}}/><button type="submit" disabled={busy||!question.trim()}><Send size={18}/>{busy?'Söker…':'Fråga'}</button></form><p className={styles.note}>Enter skickar · Shift + Enter ger ny rad. Följdfrågor använder samtalets senaste meddelanden.</p>
 </div>;
}
