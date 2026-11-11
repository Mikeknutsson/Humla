'use client';

export function ForemanWidgetActions({href}: {href: string}) {
  function downloadShortcut() {
    const target = new URL(href, window.location.origin);
    const shortcut = new Blob(['[InternetShortcut]\r\nURL=' + target.href + '\r\n'], {type: 'application/internet-shortcut'});
    const url = URL.createObjectURL(shortcut);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'Humla - Mitt omrade.url';
    link.click();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  return <div style={{display:'flex', flexWrap:'wrap', gap:8, marginBlock:12}}>
    <a className="secondary" href={href} target="_blank" rel="noopener" onClick={event => {
      if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      window.open(href, '_blank', 'popup,width=440,height=610,noopener');
    }}>Öppna widget ↗</a>
    <button className="secondary" type="button" onClick={downloadShortcut}>Ladda ner skrivbordsgenväg</button>
  </div>;
}
