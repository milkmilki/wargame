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

The three normalized reserves move toward equal values. The maximum value moved
in one year is 25 percent of the current annualized net fiscal income, equivalent
to three months of income. A country with no income may still move one bundle so
a zero treasury can recover from food or manpower reserves.

## Shared Granaries

An independent country or food-pool holder balances gold, manpower, and food.
A peaceful vassal balances only its own gold and manpower because its food is
already represented once by the holder's shared granary. A country without a
valid warehouse also uses the two-resource path, preventing converted food from
being lost when no storage destination exists.

## Strategic AI

The AI does not choose conversion direction, amount, or priority. Existing
recruitment and demobilization gates continue to read the post-settlement
resources, because deciding army size under military danger is a strategic
decision rather than a currency conversion.

## Trade Boundary

Monthly trade routes produce gold only. The former automatic purchase pass,
which spent route gold on conjured food and manpower, has been removed. Trade
result arrays for food/manpower imports and costs remain as zero-filled
compatibility fields, but no settlement stage reads them into national
inventories. The annual balance is therefore the only automatic conversion
between gold, manpower, and food.
