# Unreviewed Long-Term Proposals

These are Mira's historical proposals, not accepted memory. They are not injected into episodes and have not been merged into long_term.md. The October 3 placement restrictions below were superseded by bridge 0.9.2; the October 4 bottleneck claim describes that session, not a permanent world fact.

## 2026-10-03T20:24:29

In the test world, only stone-furnace and burner-mining-drill placement is allowed; burner-inserter and iron-chest placement is rejected. A burner mining drill can auto-fuel another burner mining drill or furnace by dropping coal directly onto it (drill-to-drill fuel chains work). Burner machine fuel inventories cap at 50 items; a machine that is waiting_for_space_in_destination stops consuming fuel.

## 2026-10-03T23:45:29

Mira's placement permission in the test world is limited to `stone-furnace` and `burner-mining-drill` only. Attempting to place a `burner-inserter` or `iron-chest` returns the error "only stone-furnace and burner-mining-drill placement is allowed". Therefore furnace output cannot be auto-drained with inserters/chests by Mira; output clogging must be handled manually.

## 2026-10-04T00:50:04

In the test factory, the dominant recurring bottleneck is burner-machine fuel (coal) starvation: there is no automated coal supply, and plate outputs also accumulate with no downstream consumer. Fuel and sink logistics matter more than adding upstream machines.
