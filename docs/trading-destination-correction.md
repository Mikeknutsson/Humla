# Trading destination correction

The approved Workify article file routes external disposal and selected traded
materials to the Trading economic unit (adapter project reference 5100). A broad
Dashboard override incorrectly redirected every such revenue row to a demolition
project, including unrelated customers and orders.

`docs/restore-trading-destination.sql` corrects the existing project override
and its demolition group override in place. It preserves the cost centre rule,
raw import rows, costs, transfer ledger and genuine demolition transactions.
The original configuration and full derived facts are retained in a private
before/after audit. The destination is resolved to a single confirmed canonical
EconomicUnit through its dated membership; ambiguous recipients abort.

The same transaction corrects disposal article categories using retained names
from the approved article file. It restores affected historical published facts
and their compact display projection, checks per-row amount/date/cost-centre
conservation, and increments the report correction revision. The corrected overrides
and persisted article rules also apply to future report generations.

The maintenance script runs through a privileged maintenance connection and
requires a KPI manager identity and the report-worker lock. Repeating it after
the incorrect destination has been corrected makes no changes. No full report worker is needed for publication.
