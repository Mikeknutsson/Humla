export const internalPrintBlocks = [
  { id: '10-30', title: '10 till 30 · Entreprenad till Transport' },
  { id: '10-20', title: '10 till 20 · Entreprenad till Sortergården' },
  { id: '20-30', title: '20 till 30 · Sortergården och Transport' },
  { id: 'workshop', title: 'Till 40 · Verkstaden' },
] as const;

export function internalPrintBlock(from: string, to: string) {
  if (to === '40' && from !== '40') return 'workshop';
  if (from === '30' && to === '20') return '20-30';
  const pair = `${from}-${to}`;
  return internalPrintBlocks.find(block => block.id === pair)?.id;
}
