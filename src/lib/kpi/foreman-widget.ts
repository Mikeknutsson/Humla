export function foremanWidgetHref(period: 'month' | 'ytd', profile?: string | null) {
  const query = new URLSearchParams({ widget: period });
  if (profile) query.set('user_id', profile);
  return '/kpi/mina-enheter?' + query.toString();
}

export function foremanWidgetReturn(value: unknown) {
  if (typeof value !== 'string') return null;
  const [path, search] = value.split('?');
  if (path !== '/kpi/mina-enheter' || !search) return null;
  const query = new URLSearchParams(search);
  const widget = query.get('widget');
  const profile = query.get('user_id');
  if (widget !== 'month' && widget !== 'ytd') return null;
  if (profile && profile !== 'transport' && !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(profile)) return null;
  return foremanWidgetHref(widget, profile);
}
