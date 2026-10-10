# civ-atlas native Godot map

The ports in `scripts/atlas/` derive from guaner-334/civ-atlas,
commit `103afd3d998eac6750692a6813bf5aea03521448` (2026).
Upstream: https://github.com/guaner-334/civ-atlas

Upstream code and these ports: GNU AGPL-3.0-only. Preserve the included
LICENSE-AGPL-3.0.txt and original copyright notices when distributing.
This notice does not relicense unrelated pre-existing game code.

`scripts/atlas/war_fronts.gd` ports the sided-border orientation, tooth placement,
fantasy colours, stroke widths and zoom law from upstream
`src/render/civ/warfare.ts` (`warFront`, `frontTeeth`, `strokeFront`, `WAR_SIZE`,
`warLook`). Live/historical hostility comes from our existing GameState rather
than upstream history simulation. See `docs/atlas/WAR_FRONTS.md`.

The independent `atlas_military.tscn` adapter adds fixed state/prefecture
administration, budgets and a shared physical transport graph. Its terrain
route and curve utilities extend the AGPL atlas ports; source and changes are
documented in `docs/atlas/MILITARY_INTEGRATION.md`. No TypeScript runtime or
upstream history simulation is introduced. Existing game combat and territory
transactions retain their own original provenance.

The Earth rainfall adapter `scripts/atlas/monsoon_rainfall.gd` calls the game's
own regional environment_v1.7 algorithm, extracted into the shared
`scripts/core/rainfall_transport.gd`. This rainfall algorithm is not copied
from civ-atlas; globe wrapping, distance adaptation and explicit moisture
conversion are recorded in `docs/atlas/MONSOON.md`.

The subsequent `seasonal_circulation.gd`, `circulation_rainfall.gd` and
`climate_settlement.gd` implement the game's reduced seasonal Earth climate
and agricultural-density extension, not the original civ-atlas climate.
Their parameters, sources, compatibility and limitations are recorded in
`docs/atlas/CIRCULATION.md` (v2) and `docs/atlas/CLIMATE_LIMITS.md` (v3).
The frozen `_v2.gd` modules retain exact old generation behavior.
The Natural Earth CHN mask under tests/fixtures
is public-domain validation data only; it is not a runtime climate mask.

The LXGW WenKai GB Medium font is the original upstream subset, losslessly
converted from WOFF2 to TTF for Godot. Its original source provenance is in
FONT-SOURCES.txt and its license in OFL-LXGW-WenKai-GB.txt.

The TypeScript reference exporter is a development tool, not a runtime.
Reference runs disable river boundary/road costs and visible rivers, use
strict suitability > 1 for city eligibility, and do not generate sea routes.
# Additional native dependency ports

`scripts/atlas/delaunator.gd` ports Delaunator 5.1.0, Copyright (c) 2026
Mapbox (ISC). Its license is preserved in `LICENSE-Delaunator.txt`. The
near-collinear sign fallback uses exact floating-point expansion arithmetic.

The eastern/western grammar JSON files retain upstream data and filters under
AGPL-3.0-only. They are native runtime data, not embedded TypeScript programs.
Screenshot evidence in `docs/atlas/evidence/` depicts the upstream derivative
map and is supplied for development comparison under the upstream license.

The Earth preset uses numeric geographic data, separately from the AGPL ports:
SRTM15+ v2.7 relief distributed by GMT (Tozer et al., 2019,
https://doi.org/10.1029/2019EA000658; source https://topex.ucsd.edu/WWW_html/srtm15_plus.html),
and Natural Earth v5.1.2 land/lakes (public domain,
https://www.naturalearthdata.com/about/terms-of-use/).
Exact download URLs, source hashes, modifications and packed asset hashes are
in `earth_source.json`. GMT's already-filtered 6 arcminute relief is converted
losslessly to signed half-meter integers; Natural Earth polygons determine
water classes. The software's AGPL notice does not relicense geographic data.

`scripts/atlas/simplex.gd` translates the 3D simplex implementation from
simplex-noise 4.0.3, Copyright (c) 2024 Jonas Wagner (MIT), with original
algorithm credit to Stefan Gustavson and Peter Eastman. Its license is
preserved in `LICENSE-simplex-noise.txt`. Raster gradient tiles are separately
ported from civ-atlas `src/gen/util.ts` under the upstream AGPL.

The native inspector in `scripts/atlas/information_theme.gd` and
`information_panel.gd` follows the pinned upstream `src/ui/theme.css`,
`countryPanel.css`, `desktop.css` and `panelParts.tsx`, under AGPL-3.0-only.
`assets/atlas/ui/{flag,city,center,copy}.svg` translates the corresponding
`src/ui/icons.tsx` paths (white strokes are tinted by Godot). The route and
war icons are native companion artwork under the same license. Interface
fonts use installed system fonts, following the upstream system-font stack;
no Microsoft font files are redistributed. Our information and commands
continue to come from the existing Godot simulation.

