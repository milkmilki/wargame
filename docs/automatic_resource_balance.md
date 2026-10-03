# Automatic Resource Balance

Resource conversion is deterministic economy settlement. It is not an AI
candidate and performs no map, pathfinding, diplomacy, or threat evaluation.

## Schedule

The balance runs once every 360 simulation days, after monthly income, trade,
tribute, military finance, and half-year food production, but before monthly
reinforcement. Calling the monthly economy resolver directly does not trigger
the annual operation, so monthly forecasts retain their existing contract.

## Exchange Values

- 1 gold = 50 manpower
- 1 gold = 25 food

Only complete gold-equivalent bundles move. Remainders remain in their original
pool. Total gold-equivalent reserve value is conserved.

Conversion follows forecast deficits, not equal shares. First fund the next
360 days of cash or food shortages and the protected manpower floor, then fund
soft reserves. Receivers at the same priority share available value in
proportion to their missing gold-equivalent bundles, using deterministic
integer allocation. No missing target means no exchange.

Donors retain both their forecast survival balance and soft reserve target.
The maximum value moved in one year remains 25 percent of current annualized
net fiscal income. A country with no income may still move one bundle.
Receiving food and manpower are limited by their actual capacities before
allocation. The whole proposal is revalidated before committing; a rejected
proposal deducts nothing.

## Shared Granaries

An independent country or food-pool holder balances gold, manpower, and food.
A peaceful vassal balances only its own gold and manpower because its food is
already represented once by the holder's shared granary. A country without a
valid warehouse also uses the two-resource path, preventing converted food from
being lost when no storage destination exists.

## Strategic AI

ResourceForecastRules supplies the survival and reserve targets. No military
target or threat search is performed during conversion. Shared pool inputs
are updated and derived forecasts invalidated after an accepted conversion;
subsequent countries cannot reuse the earlier inventory. Recruitment and
demobilization then use the post-settlement resources. See
[resource_forecast.md](resource_forecast.md) for the common decision contract.

## Trade Boundary

Monthly trade routes produce gold only. The former automatic purchase pass,
which spent route gold on conjured food and manpower, has been removed. Trade
result arrays for food/manpower imports and costs remain as zero-filled
compatibility fields, but no settlement stage reads them into national
inventories. The annual balance is therefore the only automatic conversion
between gold, manpower, and food.
