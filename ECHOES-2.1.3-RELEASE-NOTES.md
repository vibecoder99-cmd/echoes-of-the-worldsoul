# Echoes of the Worldsoul 2.1.3

## Interaction Reliability & Feedback Maintenance Release

Echoes 2.1.3 improves how the Client Companion communicates interaction
results. Major controls now make it clearer when an action was accepted,
already current, unavailable, or failed to dispatch, and the Worldsoul Core
now functions as an intentional communion/readout interaction using existing
authoritative character state.

## Highlights

- The Worldsoul Core now requests existing authoritative character state and
  presents a concise summary of Essence, Mastery rank, Attuned Items, Rack
  occupancy, World Threat, and Crucible investment.
- Major server-bound controls immediately report dispatch failures instead of
  entering false pending states.
- Already-current and unavailable actions now receive explicit, truthful
  acknowledgement.
- Missing or failed client callbacks propagate visibly, while optional debug
  traces identify action, activation source, and result.
- Keyboard, mouse, and reduced-motion interaction acknowledgement now follow
  the same reliable paths.
- Semantic feedback is clearer across Mastery, Talents, World Threat, the
  Crucible, Attunement Rack, Legacy Forge, and Visage.
- The minimap tooltip now accurately describes its open/close interaction.

## Upgrade

No progression reset is required. There are no gameplay balance changes in
this maintenance release. Existing 2.1.0, 2.1.1, and 2.1.2 progression remains
compatible.

Upgrade the server package and Client Companion AddOn together using the normal
installer workflow with `--target-version 2.1.3`.

The Client Companion wire protocol remains version 1.

## Troubleshooting

Optional client interaction tracing is disabled by default. Use
`/echoesui debug on` while reproducing an interaction and `/echoesui debug off`
afterward. Client-local actions do not generate fake server traffic.

## Community testing

Special thanks to Reddit user Economy_Progress6405 for the detailed video
troubleshooting that exposed several interaction-feedback ambiguities, and to
Weird_Expert_1999 for earlier real-world testing and reports.
