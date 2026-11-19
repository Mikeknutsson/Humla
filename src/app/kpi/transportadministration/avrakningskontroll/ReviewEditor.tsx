"use client";

import {useActionState, useState} from "react";
import {saveReview} from "./actions";
import {reviewLabels, type RowReview} from "./review";
import styles from "./review.module.css";

const date = new Intl.DateTimeFormat("sv-SE", {dateStyle:"short", timeStyle:"short", timeZone:"Europe/Stockholm"});

export default function ReviewEditor({row, month, page, review, embedded=false}: {
 row: RowReview & {id:string}; month:string; page:number; review:boolean; embedded?:boolean;
}) {
 const [error, action, pending] = useActionState(saveReview,"");
 const [state, setState] = useState(row.review_state);
 const [note, setNote] = useState(row.note ?? "");
 const label = row.changed_since_review ? "Underlag ändrat" : row.revision === 0 ? "Följ upp" : reviewLabels[row.review_state];

 const form = <form action={action}>
   <input type="hidden" name="id" value={row.id}/>
   <input type="hidden" name="fingerprint" value={row.fingerprint}/>
   <input type="hidden" name="revision" value={row.revision}/>
   <input type="hidden" name="month" value={month}/>
   <input type="hidden" name="page" value={page}/>
   <input type="hidden" name="review" value={review ? "1" : "0"}/>
   <label>Arbetsstatus
    <select name="state" value={state} onChange={event => setState(event.target.value as RowReview["review_state"])}>
     {Object.entries(reviewLabels).map(([value, name]) => <option value={value} key={value}>{name}</option>)}
    </select>
   </label>
   <label>{row.changed_since_review ? "Tidigare anteckning" : "Anteckning"}
    <textarea name="note" rows={3} maxLength={1000} required={state === "reviewed"}
      value={note} onChange={event => setNote(event.target.value)}/>
   </label>
   {row.updated_at && <small>Senast sparad {date.format(new Date(row.updated_at))}</small>}
   {error && <p role="alert">{error}</p>}
   <button className="secondary" disabled={pending}>{pending ? "Sparar…" : "Spara"}</button>
  </form>;
 return embedded ? <div className={styles.review}>{form}</div> : <details className={styles.review}><summary>{label}</summary>{form}</details>;
}
