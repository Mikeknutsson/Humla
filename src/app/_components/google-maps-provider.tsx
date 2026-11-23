'use client';

import {createContext, useContext, type ReactNode} from 'react';

const GoogleMapsKey = createContext<string | null>(null);

export function GoogleMapsProvider({browserKey, children}: {browserKey: string | null; children: ReactNode}) {
  return <GoogleMapsKey.Provider value={browserKey}>{children}</GoogleMapsKey.Provider>;
}

export function useGoogleMapsKey() {
  return useContext(GoogleMapsKey);
}
