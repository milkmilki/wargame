# Map Generation Pipeline

## Authority Boundaries

The map has three distinct kinds of data. Do not write derived rendering data
back into either of the first two layers.

1. **Geography authority**: packed elevation, land mask, `province_ids`, and
   normalized natural-feature points.
2. **Simulation authority**: cities, `Edge` transport records, owners, docks,
   diplomacy, and armies.
3. **Rendering derivatives**: curved boundary segments, soft boundary images,
   smoothed river paths, ribbons, lookup textures, and LOD state.

`province_ids` is authoritative for province topology. Boundary smoothing must
return an object marked `render_only` and must never rebuild province ownership
from filtered pixels. The zero-elevation terrain crossing remains authoritative
for the visible 3D coast.

## Generation Order

```text
elevation and land mask
-> settlement candidates
-> land-connected province raster
-> shared province-boundary graph
-> directed river features
-> docks and transport edges
-> optional political mask
-> simulation state
-> render-only curves, textures, and meshes
```

Roads and rivers consume the province raster. They must not reshape it. Land
components without a settlement remain unassigned instead of being attached to
a province across water.

## Natural Feature Contract

`MapFeatureContract` owns the versioned river schema. Each river contains:

- a stable non-negative `id`;
- `points` ordered from source to downstream end;
- explicit `flow_direction = points_downstream`;
- `source_kind` identifying boundary generation, procedural hydrology, or import;
- positive source and mouth width multipliers;
- optional upstream and downstream river IDs.

The current boundary generator emits independent rivers ending at the coast.
A future hydrology generator may emit tributaries by filling `upstream_ids` and
`downstream_id`, provided the resulting graph is acyclic. It must still emit
normalized map coordinates and pass `MapFeatureContract.validate_rivers()`.

`GameState.river_features` is the structured authority. `river_paths` is a
compatibility projection for existing transport code and version 3/4 map files.
New version 5 map files persist both and validation rejects disagreement.

## Rendering Rules

- Province curves are derived once from the province raster and cached across
  ownership or diplomacy changes.
- Country borders reclassify the cached shared edges; they do not rescan or
  filter province ownership.
- River smoothing is derived from authoritative points and is clamped to a
  0.45 province-raster-pixel corridor around each source segment.
- River mesh UV.x stores source-to-mouth progress and UV.y stores bank side.
- Coast ink comes from interpolated terrain elevation at zero metres, not the
  province raster coastline.

These constraints allow rendering algorithms to change without invalidating
pathfinding, docks, province adjacency, save files, or procedural generation.
