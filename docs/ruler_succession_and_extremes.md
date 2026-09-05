# Ruler Succession And Extreme Archetypes

Ruler succession is a deterministic calendar event rather than an AI action.
Each reign lasts an inclusive random range of 10 through 30 years, with one
year equal to 360 simulation days. The world seed, nation id, and ruler
revision determine the duration, name, archetype, and traits, so replay and
save loading remain deterministic across platforms.

On the due day the ruler name, archetype, and trait set are rerolled. The new
identity updates the trade policy, cached army and city modifiers, naming
revision, and trade forecast inputs.

## Extreme Examples

- Conqueror: 2.0 morale and 2.0 field-defense multipliers, much stronger
  aggression and manpower, with expensive upkeep and food consumption.
- Guardian: 2.0 trade and city-defense multipliers, strong reserves and food
  economy, and no offensive campaigns.
- Puppet ruler: enfeoff preference 5.0, centralization preference 0.05, no
  offensive campaigns, and a concrete political rule that repeatedly grants
  the farthest direct territory to vassals every 180 days in peacetime until
  only a connected three-city capital core remains. It never revokes vassals
  during the same reign.

All other archetype and trait modifiers continue to compose through
`RulerProfile.modifiers()`.
