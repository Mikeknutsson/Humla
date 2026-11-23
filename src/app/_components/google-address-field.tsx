'use client';

import {useEffect, useRef, useState} from 'react';
import {MapPin} from 'lucide-react';

type Place = {id?: string; formattedAddress?: string; fetchFields: (options: {fields: string[]}) => Promise<unknown>};
type SelectEvent = Event & {placePrediction: {toPlace: () => Place}};
type Places = {Place: new (options: {id: string}) => Place; PlaceAutocompleteElement: new (options: {includedRegionCodes: string[]}) => HTMLElement};
type Routes = {Route: {computeRoutes(options: {
  origin: string | Place; destination: string | Place; travelMode: 'DRIVING'; fields: string[];
}): Promise<{routes: {distanceMeters?: number; durationMillis?: number}[]}>}};
type Maps = {importLibrary(name: 'places'): Promise<Places>; importLibrary(name: 'routes'): Promise<Routes>};
type GoogleWindow = Window & {google?: {maps: Maps}; humlaMapsReady?: () => void};
const mapsKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
let pendingPlaces: Promise<Places> | undefined;

function loadPlaces() {
  const browser = window as GoogleWindow;
  if (browser.google?.maps?.importLibrary) return browser.google.maps.importLibrary('places');
  pendingPlaces ??= new Promise<Places>((resolve, reject) => {
    const script = document.createElement('script');
    const timeout = window.setTimeout(() => fail(), 12000);
    const fail = () => {
      window.clearTimeout(timeout);
      delete browser.humlaMapsReady;
      script.remove();
      reject(new Error('Google Maps could not be loaded'));
    };
    browser.humlaMapsReady = () => {
      window.clearTimeout(timeout);
      delete browser.humlaMapsReady;
      browser.google?.maps?.importLibrary('places').then(resolve, reject);
    };
    script.onerror = fail;
    script.async = true;
    script.src = `https://maps.googleapis.com/maps/api/js?${new URLSearchParams({
      key: mapsKey ?? '', loading: 'async', callback: 'humlaMapsReady', language: 'sv', region: 'SE', v: 'weekly',
    })}`;
    document.head.append(script);
  }).catch(error => {
    pendingPlaces = undefined;
    throw error;
  });
  return pendingPlaces;
}

export const googleMapsAvailable = Boolean(mapsKey);

export async function googleRoadEstimate(origin: {address: string; id?: string}, destination: {address: string; id?: string}) {
  const {Place} = await loadPlaces();
  const {Route} = await (window as GoogleWindow).google!.maps.importLibrary('routes');
  const {routes} = await Route.computeRoutes({
    origin: origin.id ? new Place({id:origin.id}) : origin.address,
    destination: destination.id ? new Place({id:destination.id}) : destination.address,
    travelMode:'DRIVING', fields:['distanceMeters','durationMillis'],
  });
  const first = routes[0];
  if (first?.distanceMeters == null || first.durationMillis == null) throw new Error('Ingen rutt');
  return {miles:String(Number((first.distanceMeters / 10000).toFixed(3))),
    driveMinutes:String(Number((first.durationMillis / 60000).toFixed(1)))};
}

export function GoogleAddressField({label, value, onChange, className}: {
  label: string; value: string; onChange: (value: string, placeId?: string) => void; className?: string;
}) {
  const [open, setOpen] = useState(false);
  const [error, setError] = useState('');
  const mount = useRef<HTMLDivElement>(null);
  const onSelected = useRef(onChange);
  useEffect(() => {onSelected.current = onChange;}, [onChange]);
  useEffect(() => {
    if (!open || !mapsKey || !mount.current) return;
    let active = true;
    const container = mount.current;
    loadPlaces().then(({PlaceAutocompleteElement}) => {
      if (!active) return;
      const input = new PlaceAutocompleteElement({includedRegionCodes: ['se']});
      input.setAttribute('aria-label', label);
      input.addEventListener('gmp-error', () => setError('Google Maps kunde inte söka. Fyll i adressen manuellt.'));
      input.addEventListener('gmp-select', async (event: Event) => {
        try {
          const place = (event as SelectEvent).placePrediction.toPlace();
          await place.fetchFields({fields: ['id', 'formattedAddress']});
          if (!active || !place.formattedAddress) return;
          onSelected.current(place.formattedAddress, place.id);
          setOpen(false);
        } catch {
          if (active) setError('Google Maps kunde inte hämta adressen.');
        }
      });
      container.replaceChildren(input);
      input.focus();
    }).catch(() => {if (active) setError('Google Maps kunde inte laddas.');});
    return () => {active = false; container.replaceChildren();};
  }, [label, open]);

  const fallbackUrl = `https://www.google.com/maps/search/?${new URLSearchParams({api: '1', query: value || 'Sverige'})}`;
  return <div className={className}>
    <label>{label}<input value={value} maxLength={240} onChange={event => onChange(event.target.value)}/></label>
    {mapsKey ? <button type="button" className="secondary" aria-expanded={open}
      onClick={() => {setError(''); setOpen(!open);}}><MapPin size={14}/> Sök i Google Maps</button>
      : <a className="secondary" href={fallbackUrl} target="_blank" rel="noreferrer"><MapPin size={14}/> Öppna Google Maps</a>}
    {open && <div ref={mount}/>}
    {error && <small role="status">{error}</small>}
  </div>;
}
