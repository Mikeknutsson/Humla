# Monthly comparison periods

The monthly API reads the Hub report for the selected fiscal year and the previous fiscal year, with the same calendar month, cost center and canonical filters. It preserves both month and fiscal YTD from each report. January–August remain in their September-start fiscal year.

The web report, department PDFs and Excel comparison sheets display Month, YTD, same month previous year and corresponding YTD previous year. Metrics match by metric key and units match by canonical Humla unit ID. A renamed unit uses its current label. Missing or failed comparison evidence remains missing, never a fabricated zero.

The old introductory controls and large KPI cards were removed as requested. Current report filters determine the displayed period. Department PDFs continue to show KST 20 and KST 30 separately; Excel follows the selected scope. Source transaction details remain evidence for the selected period.

Validation: production Hub values for September 2026 and 2025 for both departments; keyed metric alignment, canonical unit identity and absent prior data; TypeScript/build; rendered leadership and detailed PDFs. Historical time coverage remains incomplete until the separately approved time import is completed. Workify reconciliation and missing overhead evidence remain explicitly identified.
