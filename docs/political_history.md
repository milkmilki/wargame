# Political History Viewer

## Objective

Add a read-only political timeline. At a fixed interval, capture territory and
diplomatic state so the player can pause and inspect earlier borders and
relations without rewinding the simulation.

## Behavior

- Capture day 0 and then one snapshot every 30 committed simulation days.
- Store city controller, recognized owner, nation alive state, bilateral
  relations, truces, war objectives, suzerainty, and rebellion metadata.
- The rightmost timeline position is always the live state.
- Selecting an older position pauses simulation and renders a detached
  historical `GameState` view.
- Historical views contain no armies, battles, campaign arrows, or trade
  routes.
- Clicking historical territory selects its nation and shows historical wars,
  allies, subjects, and overlord status. Current resources are not presented as
  historical values.
- Returning to the live position restores the pause state and map mode that
  existed before history was opened.
- Starting or loading a new world clears the old timeline.

## Boundaries

- History is memory-only and is not written to map-definition files.
- A historical point cannot become a new simulation branch.
- Nation identity and color use the current identity record; political state
  and territorial state come from the selected snapshot.

## Verification

- Unit tests cover capture cadence, snapshot detachment, historical relations,
  and the absence of military state.
- Scene smoke tests verify that the timeline is present and switches between a
  historical view and the live view.
