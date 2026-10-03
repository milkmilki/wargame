# Annual Automatic Conversion Removed

## Decision

The money/food separation replaces annual automatic gold/manpower/food
balancing. The annual resolver, ResourceBalanceRules module, exchange quota
and last_automatic_resource_balance records no longer exist. There is no
replacement automatic conversion pass.

Recruitment and refill consume manpower and require food qualification.
Money controls combat quality through the last actual military payment,
not recruitable headcount. See [military_funding_and_food.md](military_funding_and_food.md)
and [resource_forecast.md](resource_forecast.md).

## Retained Resource Flows

Normal trade routes, tribute, harvest, manpower production and one-time
political resource transfers keep their existing settlement rules. This
change does not add or remove a separate trade purchasing feature.

Current trade routes produce gold only. Food/manpower purchase arrays are
already zero-filled compatibility fields in this revision; removing annual
conversion does not activate them or conjure purchases into inventories.

## Regression

The existing tests/automatic_resource_balance.gd now verifies ordinary
monthly and half-year settlement at days 180, 360 and 720 with zero automatic
exchange. Income, court expense and storage-capacity clipping still apply.
