'use client';

import {useEffect, useEffectEvent, useId, useRef, useState} from 'react';
import {MapPin} from 'lucide-react';
import styles from './google-address-field.module.css';
import {useGoogleMapsKey} from './google-maps-provider';

export type Point = {lat: number; lng: number};
type LatLng = {toJSON: () => Point};
type MapEvent = {latLng?: LatLng | null};
type Listener = {remove: () => void};
type MapView = {
  addListener: (event: 'click', callback: (event: MapEvent) => void) => Listener;
  panTo: (point: Point) => void;
  setZoom: (zoom: number) => void;
};
type Marker = {
  addListener: (event: 'dragend', callback: (event: MapEvent) => void) => Listener;
  setPosition: (point: Point) => void;
  setMap: (map: MapView | null) => void;
};
type PointChoice = {address: string; placeId?: string; point?: Point};
const regionalCenter = {lat:56.174, lng:14.77};

type Place = {id?: string; formattedAddress?: string; location?: LatLng | null; fetchFields: (options: {fields: string[]}) => Promise<unknown>};
type SelectEvent = Event & {placePrediction: {toPlace: () => Place}};
type PlaceAutocomplete = HTMLElement & {value: string; placeholder: string; maxlength: number};
type Places = {Place: new (options: {id: string}) => Place; PlaceAutocompleteElement: new (options: {includedRegionCodes: string[]}) => PlaceAutocomplete};
type GoogleLocation = {address: string; id?: string; point?: Point};
type GoogleWaypoint = string | Place | Point;
type RoadMetrics = {distanceMeters?: number; durationMillis?: number};
type Routes = {
  Route: {computeRoutes(options: {
    origin: GoogleWaypoint; destination: GoogleWaypoint; travelMode: 'DRIVING'; fields: string[];
  }): Promise<{routes: RoadMetrics[]}>};
  RouteMatrix: {computeRouteMatrix(options: {
    origins: GoogleWaypoint[]; destinations: GoogleWaypoint[]; travelMode: 'DRIVING'; fields: string[];
  }): Promise<{matrix: {rows: {items: RoadMetrics[]}[]}}>};
};
type AddressValidation = {AddressValidation: {fetchAddressValidation(options: {
  address: {regionCode: string; addressLines: string[]};
}): Promise<{address?: {formattedAddress?: string}; verdict?: {
  addressComplete?: boolean; validationGranularity?: string; hasUnconfirmedComponents?: boolean;
  hasInferredComponents?: boolean; hasReplacedComponents?: boolean;
}}>}};
type GeocodedAddress = {
  types: string[];
  formatted_address: string;
  partial_match?: boolean;
  address_components: {long_name: string; types: string[]}[];
  geometry: {location: LatLng};
};
type Bounds = {south: number; west: number; north: number; east: number};
type Maps = {
  importLibrary(name: 'places'): Promise<Places>;
  importLibrary(name: 'routes'): Promise<Routes>;
  importLibrary(name: 'addressValidation'): Promise<AddressValidation>;
  importLibrary(name: 'geocoding'): Promise<{Geocoder: new () => {
    geocode(request: {location: Point} | {address: string; componentRestrictions: {country: string}; bounds?: Bounds; fulfillOnZeroResults?: boolean}):
      Promise<{results: GeocodedAddress[]}>;
  }}>;
  importLibrary(name: 'maps'): Promise<{Map: new (host: HTMLElement, options: {
    center: Point; zoom: number; clickableIcons: boolean; streetViewControl: boolean;
  }) => MapView}>;
  importLibrary(name: 'marker'): Promise<{Marker: new (options: {
    draggable: boolean; title: string;
  }) => Marker}>;
};
type GoogleWindow = Window & {google?: {maps: Maps}; humlaMapsReady?: () => void};
let pendingPlaces: Promise<Places> | undefined;

function loadPlaces(mapsKey: string) {
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
      key: mapsKey, loading: 'async', callback: 'humlaMapsReady', language: 'sv', region: 'SE', v: 'weekly',
    })}`;
    document.head.append(script);
  }).catch(error => {
    pendingPlaces = undefined;
    throw error;
  });
  return pendingPlaces;
}

function parsePoint(value: string): Point | undefined {
  const match = value.match(/^\s*(-?\d{1,3}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)\s*$/);
  if (!match) return;
  const lat = Number(match[1]);
  const lng = Number(match[2]);
  if (Math.abs(lat) <= 90 && Math.abs(lng) <= 180) return {lat, lng};
}

function pointLabel(point: Point) {
  return `${point.lat.toFixed(6)}, ${point.lng.toFixed(6)}`;
}

function waypoint({address,id,point}: GoogleLocation, Place: Places['Place']): GoogleWaypoint {
  return point ?? parsePoint(address) ?? (id ? new Place({id}) : address);
}

function roadEstimate(metrics?: RoadMetrics) {
  if (metrics?.distanceMeters == null || metrics.durationMillis == null) return undefined;
  return {miles:String(Number((metrics.distanceMeters / 10000).toFixed(3))),
    driveMinutes:String(Number((metrics.durationMillis / 60000).toFixed(1)))};
}

const roadFields = ['distanceMeters','durationMillis'];

export async function reverseGeocodePoint(mapsKey: string, point: Point) {
  await loadPlaces(mapsKey);
  const {Geocoder} = await (window as GoogleWindow).google!.maps.importLibrary('geocoding');
  const {results} = await new Geocoder().geocode({location:point});
  return results;
}

export async function geocodeSwedishAddress(mapsKey: string, address: string, bounds?: Bounds) {
  await loadPlaces(mapsKey);
  const maps = (window as GoogleWindow).google?.maps;
  if (!maps) throw new Error('Google Maps is unavailable');
  const {Geocoder} = await maps.importLibrary('geocoding');
  try {
    const {results} = await new Geocoder().geocode({address,componentRestrictions:{country:'SE'},bounds,fulfillOnZeroResults:true});
    return results;
  } catch (error) {
    if (error && typeof error==='object' && 'code' in error && error.code==='ZERO_RESULTS') return [];
    throw error;
  }
}

export async function googleRoadEstimate(mapsKey: string, origin: GoogleLocation, destination: GoogleLocation) {
  const {Place} = await loadPlaces(mapsKey);
  const {Route} = await (window as GoogleWindow).google!.maps.importLibrary('routes');
  const {routes} = await Route.computeRoutes({
    origin:waypoint(origin,Place), destination:waypoint(destination,Place), travelMode:'DRIVING', fields:roadFields,
  });
  const estimate = roadEstimate(routes[0]);
  if (!estimate) throw new Error('Ingen rutt');
  return estimate;
}

async function computeGoogleRouteMatrix(mapsKey: string, origins: GoogleLocation[], destinations: GoogleLocation[]) {
  const {Place} = await loadPlaces(mapsKey);
  const {RouteMatrix} = await (window as GoogleWindow).google!.maps.importLibrary('routes');
  const {matrix} = await RouteMatrix.computeRouteMatrix({
    origins:origins.map(origin => waypoint(origin,Place)),
    destinations:destinations.map(destination => waypoint(destination,Place)),
    travelMode:'DRIVING', fields:roadFields,
  });
  return matrix.rows;
}

export async function googleRouteMatrix(mapsKey: string, origins: GoogleLocation[], destination: GoogleLocation) {
  const rows = await computeGoogleRouteMatrix(mapsKey,origins,[destination]);
  return origins.map((_, index) => roadEstimate(rows[index]?.items[0]));
}

export async function googleReturnRouteMatrix(mapsKey: string, origin: GoogleLocation, destinations: GoogleLocation[]) {
  const rows = await computeGoogleRouteMatrix(mapsKey,[origin],destinations);
  return destinations.map((_, index) => roadEstimate(rows[0]?.items[index]));
}

export async function validateGoogleAddress(mapsKey: string, address: string) {
  await loadPlaces(mapsKey);
  const {AddressValidation} = await (window as GoogleWindow).google!.maps.importLibrary('addressValidation');
  const {address: result, verdict} = await AddressValidation.fetchAddressValidation({
    address:{regionCode:'SE',addressLines:[address]},
  });
  return {
    formattedAddress:result?.formattedAddress,
    confirmed:Boolean(verdict?.addressComplete && ['PREMISE','SUB_PREMISE'].includes(verdict.validationGranularity ?? '') &&
      !verdict.hasUnconfirmedComponents && !verdict.hasInferredComponents && !verdict.hasReplacedComponents),
  };
}

function MapPicker({mapsKey, value, placeId, point, label, followsInput, onChoose, onClose}: {
  mapsKey: string; value: string; placeId?: string; point?: Point; label: string; followsInput?: boolean;
  onChoose: (choice: PointChoice) => void; onClose: () => void;
}) {
  const [choice, setChoice] = useState<PointChoice>();
  const [error, setError] = useState('');
  const [resolving,setResolving] = useState(false);
  const searchHost = useRef<HTMLDivElement>(null);
  const mapHost = useRef<HTMLDivElement>(null);
  const syncSelection = useRef<(selection: PointChoice) => void>(null);
  const caption = useId();
  const initialChoice = useEffectEvent(() => ({address:value,placeId,point}));

  useEffect(() => {
    const container = searchHost.current;
    const mapContainer = mapHost.current;
    if (!mapContainer) return;
    let active = true;
    let selectionVersion = 0;
    let pin: Marker | undefined;
    const listeners: Listener[] = [];

    async function initialize() {
      const {PlaceAutocompleteElement, Place} = await loadPlaces(mapsKey);
      const maps = (window as GoogleWindow).google!.maps;
      const [{Map}, {Marker}] = await Promise.all([maps.importLibrary('maps'), maps.importLibrary('marker')]);
      if (!active || !mapContainer) return;
      const selection = initialChoice();
      const initial = selection.point ?? parsePoint(selection.address);
      const map = new Map(mapContainer, {center:initial ?? regionalCenter, zoom:initial ? 17 : 9, clickableIcons:false, streetViewControl:false});
      const marker = pin = new Marker({draggable:true, title:'Leveranspunkt'});
      function showPin(point: Point, selection: PointChoice, zoom = false) {
        marker.setPosition(point);
        marker.setMap(map);
        setChoice(selection);
        if (zoom) {
          map.panTo(point);
          map.setZoom(17);
        }
      }

      async function pickPoint(event: MapEvent) {
        if (!event.latLng) return;
        const request = ++selectionVersion;
        setError('');
        const point = event.latLng.toJSON();
        const coordinates = {address:pointLabel(point),point};
        showPin(point,coordinates);
        if (!followsInput) return;
        setResolving(true);
        try {
          const {Geocoder} = await maps.importLibrary('geocoding');
          const {results} = await new Geocoder().geocode({location:point});
          if (!active || request !== selectionVersion) return;
          const address = results.find(result => result.types.some(type => ['street_address','premise','subpremise'].includes(type)));
          if (address?.formatted_address) setChoice({...coordinates,address:address.formatted_address});
        } catch {
          if (active && request === selectionVersion) setError('Ingen gatuadress kunde hämtas. Kartnålen går fortfarande att använda.');
        } finally {
          if (active && request === selectionVersion) setResolving(false);
        }
      }

      listeners.push(map.addListener('click', event => void pickPoint(event)), marker.addListener('dragend', event => void pickPoint(event)));
      if (container && !followsInput) {
        const search = new PlaceAutocompleteElement({includedRegionCodes:['se']});
        search.setAttribute('aria-label', `Sök på kartan för ${label.toLowerCase()}`);
        search.addEventListener('gmp-error', () => {
          if (active) setError('Adressökningen kunde inte öppnas. Du kan välja en punkt på kartan.');
        });
        search.addEventListener('gmp-select', async event => {
          const request = ++selectionVersion;
          setError('');
          try {
            const place = (event as SelectEvent).placePrediction.toPlace();
            await place.fetchFields({fields:['id','formattedAddress','location']});
            if (!active || request !== selectionVersion) return;
            if (!place.location) {
              setError('Platsen saknar en punkt. Välj en punkt på kartan.');
              return;
            }
            const point = place.location.toJSON();
            showPin(point, place.formattedAddress && place.id
              ? {address:place.formattedAddress, placeId:place.id}
              : {address:pointLabel(point)}, true);
          } catch {
            if (active && request === selectionVersion) setError('Platsen kunde inte hämtas.');
          }
        });
        container.replaceChildren(search);
        search.focus();
      }

      async function updatePin(selection: PointChoice) {
        const request = ++selectionVersion;
        setResolving(false);
        setError('');
        const point = selection.point ?? parsePoint(selection.address);
        if (point) {
          showPin(point,selection,true);
          return;
        }
        marker.setMap(null);
        setChoice(undefined);
        if (!selection.placeId) return;
        try {
          const previous = new Place({id:selection.placeId});
          await previous.fetchFields({fields:['location']});
          if (active && request === selectionVersion && previous.location) showPin(previous.location.toJSON(),selection,true);
        } catch {
          if (active && request === selectionVersion) setError('Adressen kunde inte visas på kartan.');
        }
      }
      syncSelection.current = selection => void updatePin(selection);
      syncSelection.current(selection);
    }

    void initialize().catch(() => {
      if (active) setError('Google Maps kunde inte laddas. Du kan fylla i adressen manuellt.');
    });
    return () => {
      active = false;
      syncSelection.current = null;
      listeners.forEach(listener => listener.remove());
      pin?.setMap(null);
      container?.replaceChildren();
      mapContainer.replaceChildren();
    };
  }, [label,mapsKey,followsInput]);

  useEffect(() => {syncSelection.current?.({address:value,placeId,point});},[value,placeId,point]);

  return <section className={styles.picker} data-map-picker aria-labelledby={caption}>
    <p id={caption}>{followsInput ? 'Välj ett adressförslag eller sätt kartnålen vid infarten.' : 'Sök en plats, klicka på kartan eller dra nålen till infarten.'}</p>
    {!followsInput && <div ref={searchHost}/>}
    <div ref={mapHost} className={styles.map}/>
    {error && <p role="status">{error}</p>}
    <div className={styles.actions}>
      <button type="button" className="secondary" disabled={!choice || resolving} onClick={() => choice && onChoose(choice)}>Använd kartnålen</button>
      <button type="button" className="secondary" onClick={onClose}>Stäng kartan</button>
      {choice && <small aria-live="polite">{resolving ? 'Söker adress vid kartnålen…' : choice.address}</small>}
    </div>
  </section>;
}

function InlinePlaceSearch({mapsKey, label, value, placeholder, onChange, onUnavailable}: {
  mapsKey: string; label: string; value: string; placeholder?: string;
  onChange: (value: string, placeId?: string, point?: Point) => void; onUnavailable: () => void;
}) {
  const host = useRef<HTMLDivElement>(null);
  const element = useRef<PlaceAutocomplete>(null);
  const [status, setStatus] = useState('Laddar adressförslag…');
  const currentValue = useEffectEvent(() => value);
  const change = useEffectEvent(onChange);
  const unavailable = useEffectEvent(onUnavailable);

  useEffect(() => {
    const container = host.current;
    if (!container) return;
    let active = true;
    let selection = 0;
    async function initialize() {
      const {PlaceAutocompleteElement} = await loadPlaces(mapsKey);
      if (!active || !container) return;
      const search = new PlaceAutocompleteElement({includedRegionCodes:['se']});
      search.value = currentValue();
      search.placeholder = placeholder ?? 'Sök adress eller plats';
      search.maxlength = 240;
      search.setAttribute('aria-label',label);
      search.addEventListener('input', () => {
        selection += 1;
        setStatus('');
        change(search.value);
      });
      search.addEventListener('gmp-error', () => {
        if (active) unavailable();
      });
      search.addEventListener('gmp-select', async event => {
        const request = ++selection;
        setStatus('');
        try {
          const place = (event as SelectEvent).placePrediction.toPlace();
          await place.fetchFields({fields:['id','formattedAddress','location']});
          if (!active || request !== selection) return;
          if (!place.id || !place.formattedAddress) {
            setStatus('Välj en adress i listan eller använd kartnålen.');
            return;
          }
          search.value = place.formattedAddress;
          change(place.formattedAddress,place.id,place.location?.toJSON());
        } catch {
          if (active && request === selection) setStatus('Förslaget kunde inte hämtas. Välj en adress igen eller använd kartnålen.');
        }
      });
      element.current = search;
      container.replaceChildren(search);
      setStatus('');
    }
    void initialize().catch(() => {if (active) unavailable();});
    return () => {
      active = false;
      element.current = null;
      container.replaceChildren();
    };
  },[label,mapsKey,placeholder]);

  useEffect(() => {
    const search = element.current;
    if (search && search.value !== value) search.value = value;
  },[value]);

  return <div>
    <div>{label}</div>
    <div ref={host}/>
    {status && <small role="status">{status}</small>}
  </div>;
}

export function GoogleAddressField({label, value, placeId, point, onChange, onCommit, placeholder, className, autocomplete}: {
  label: string; value: string; placeId?: string; point?: Point; onChange: (value: string, placeId?: string, point?: Point) => void;
  onCommit?: (value: string) => void; placeholder?: string; className?: string; autocomplete?: boolean;
}) {
  const mapsKey = useGoogleMapsKey();
  const [open, setOpen] = useState(false);
  const [searchUnavailable, setSearchUnavailable] = useState(false);
  const trigger = useRef<HTMLButtonElement>(null);
  const fallbackUrl = `https://www.google.com/maps/search/?${new URLSearchParams({api: '1', query: value || 'Sverige'})}`;
  function close() {
    setOpen(false);
    trigger.current?.focus();
  }
  return <div className={className}>
    {autocomplete && mapsKey && !searchUnavailable ? <InlinePlaceSearch mapsKey={mapsKey} label={label} value={value} placeholder={placeholder}
      onChange={onChange} onUnavailable={() => setSearchUnavailable(true)}/> :
    <label>{label}<input value={value} placeholder={placeholder} maxLength={240} onBlur={event => onCommit?.(event.currentTarget.value)}
      onKeyDown={event => {
        if (event.key === 'Enter' && onCommit) {
          event.preventDefault();
          onCommit(event.currentTarget.value);
        }
      }} onChange={event => {
      if (!autocomplete) setOpen(false);
      onChange(event.target.value);
    }}/></label>}
    {searchUnavailable && <small role="status">Adressförslagen är tillfälligt otillgängliga. Skriv in adressen eller välj på kartan.</small>}
    {mapsKey ? <button type="button" className="secondary" aria-expanded={open} ref={trigger}
      onClick={() => setOpen(!open)}><MapPin size={14}/> Välj på kartan</button>
      : <a className="secondary" href={fallbackUrl} target="_blank" rel="noreferrer"><MapPin size={14}/> Öppna Google Maps</a>}
    {open && mapsKey && <MapPicker mapsKey={mapsKey} label={label} value={value} placeId={placeId} point={point}
      followsInput={autocomplete && !searchUnavailable} onClose={close}
      onChoose={choice => {
        onChange(choice.address,choice.placeId,autocomplete ? choice.point : undefined);
        if (!autocomplete) close();
      }}/>}
  </div>;
}
