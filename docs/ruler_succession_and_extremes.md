# Ruler Succession And Extreme Archetypes

Ruler succession is a deterministic calendar event rather than an AI action.
Each reign lasts an inclusive random range of 1 through 50 years, with one
year equal to 360 simulation days. The world seed, nation id, and ruler
revision determine the duration, name, archetype, and traits, so replay and
save loading remain deterministic across platforms.

On the due day the existing crown prince succeeds with the same person ID,
name, archetype, and traits. An unfinished succession war delays accession.
The new identity updates the trade policy, cached army and city modifiers, naming
revision, and trade forecast inputs.

Succession also reruns the existing capital valuation. It does not require a
move: the old capital remains in the candidate set and keeps its accumulated
capital-development duration when it wins again. Only a genuinely better
candidate becomes the new capital and restarts that duration.

Person names use a random surname and one or two random Han characters;
duplicates are allowed and never gain numeric suffixes. Blood relationships
use person IDs rather than surname matching. Empire recognition and hereditary
royal titles are specified in [empire_royal_titles.md](empire_royal_titles.md).

## Extreme Examples

- Conqueror: 5.0 attack and field-defense multipliers, 2.0 morale and positive
  war-benefit multipliers, and 0.5 campaign-requirement, upkeep, and
  offensive-interval multipliers, plus stronger aggression and
  manpower. A conqueror vassal always resists centralization and receives twice
  the normal civil-war uprising armies. The shorter interval composes with the
  existing aggression-based campaign cadence.
- Guardian: 2.0 trade and city-defense multipliers, strong reserves and food
  economy, and no offensive campaigns.
- Puppet ruler: enfeoff preference 5.0, centralization preference 0.05, no
  offensive campaigns, and a concrete political rule that repeatedly grants
  the farthest direct territory to vassals every 180 days in peacetime until
  only a connected three-city capital core remains. It never revokes vassals
  during the same reign.

All other archetype and trait modifiers continue to compose through
`RulerProfile.modifiers()`.
