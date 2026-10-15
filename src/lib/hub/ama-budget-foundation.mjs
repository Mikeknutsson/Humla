/** Lightweight validation for project-supplied AMA/BSAB references.
 * Never guesses an edition, official heading, measurement rule or code validity.
 */
export function classifyAmaReference({system,discipline,edition,code,source}) {
  const norm = v => String(v ?? '').normalize('NFKC').trim();
  const result = {system:norm(system).toUpperCase(),discipline:norm(discipline).toUpperCase(),
    edition:norm(edition),code:norm(code).toUpperCase(),source:norm(source)};
  if (!['AMA','BSAB96'].includes(result.system) ||
      !['ANLAGGNING','HUS','EL','VVS','AF'].includes(result.discipline) ||
      !result.code || !result.source) return {status:'needs_review',...result};
  if (!result.edition) return {status:'needs_review',...result};
  return {status:'reference_recorded_unverified',...result};
}
export function budgetRowFromSource({reference,sourceDocumentId,sourcePage,description,quantity,unit,unitPrice}) {
  const qty=Number(quantity),price=Number(unitPrice);
  if (!sourceDocumentId || !Number.isFinite(qty) || qty<0 || !Number.isFinite(price) || price<0)
    return {status:'needs_review',reason:'missing_provenance_or_invalid_financial_quantity'};
  if (!unit || !description) return {status:'needs_review',reason:'unit_or_description_missing'};
  return {status:'draft_requires_approval',classification:classifyAmaReference(reference ?? {}),
    sourceDocumentId,sourcePage:sourcePage??null,description,quantity:qty,unit,unitPrice:price,
    extendedPrice:Math.round(qty*price*100)/100};
}
