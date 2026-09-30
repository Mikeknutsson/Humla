// Disabled: a NEXT project reference alone does not authorize vehicle allocation.
// A future allocation workflow must explicitly classify each cost or approved group.
export async function POST(){return Response.json({error:"Automatisk fordonsmatchning av NEXT-kostnader är avstängd. Klassificera kostnader som fordon, projekt, gemensamt eller övrigt först."},{status:409});}
