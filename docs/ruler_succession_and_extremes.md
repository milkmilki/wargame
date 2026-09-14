# Ruler Succession And Extreme Archetypes

Ruler succession is a deterministic calendar event rather than an AI action.
Each reign lasts an inclusive random range of 10 through 30 years, with one
year equal to 360 simulation days. The world seed, nation id, and ruler
revision determine the duration, name, archetype, and traits, so replay and
save loading remain deterministic across platforms.

On the due day the ruler name, archetype, and trait set are rerolled. The new
identity updates the trade policy, cached army and city modifiers, naming
revision, and trade forecast inputs.

Succession also reruns the existing capital valuation. It does not require a
move: the old capital remains in the candidate set and keeps its accumulated
capital-development duration when it wins again. Only a genuinely better
candidate becomes the new capital and restarts that duration.

Rulers in one suzerainty hierarchy share the root overlord's surname. New
vassals inherit it, vassal succession keeps it, and an overlord with surviving
vassals preserves the dynasty surname when appointing a successor. Given names
remain deterministic and campaign-unique.

## Extreme Examples

- Conqueror: 2.0 morale, field-defense, and positive war-benefit multipliers,
  0.5 upkeep and offensive-interval multipliers, plus stronger aggression and
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
