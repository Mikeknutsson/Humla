# Workify article allocation and partial import

The uploaded Uppdelning Artiklar från Workify(1).xlsx was loaded into the existing Elleholms tenant register: 297 unique rules (92 project, 205 executing vehicle). Four equivalent duplicate codes were consolidated; source rows and SHA256 are retained. Register is tenant scoped and read-only through authenticated RLS. Changes require a deliberate new register version; no implicit defaults.

Detected Workify order exports use exact normalized article codes. An explicit project overrides the export project and clears normalized vehicle/person attribution. Blank project explicitly routes to the resolved executing vehicle and clears normalized project/person. Original source fields remain unchanged. Each transaction stores the rule ID and source hash. Unknown articles and missing required vehicles are quarantined. Existing imports are not rewritten.

Valid rows in completed or needs_review batches count in existing reports. Row data errors split failed insert chunks to isolate the offending transaction, whose raw source remains saved with invalid typed values cleared. Authorization/service/storage failures remain batch failures. Negative hours are held before insertion. Nonempty single-cell transactions remain reviewable; Workify attachment-only continuation lines are excluded, with the original workbook preserved.

Recent imports exposes paginated invalid transactions with full original fields. This release does not yet edit/reprocess saved review rows. Do not reimport a full file to correct individual transactions: deduplication remains in force. Account mappings continue independently and unknown cost accounts remain excluded.

Validation: synthetic mixed rows, project/vehicle exclusivity, unknown articles, negative hours, existing parser tests. Actual August Workify export: 1668 transaction rows, 1417 valid (178 project/1239 vehicle), 251 review including 40 unknown articles. Dry run only, no revenue inserted. Authenticated browser end-to-end was not available.
