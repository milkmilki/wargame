import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts/tools"))
from preprocess_hydrology import drainage, simplify


class DrainageTests(unittest.TestCase):
    def test_isolated_negative_dem_spike_does_not_cut_an_inland_river(self):
        from preprocess_hydrology import ocean_mask

        dem = np.full((40, 60), 150.0, np.float32)
        dem[20, :] = np.linspace(80, -1, 60)
        dem[20, 30] = -359.0
        self.assertFalse(ocean_mask(dem)[20 * 60 + 30])
        downstream, _, _, _, _ = drainage(dem, 1.5)
        node = 20 * 60
        while downstream[node] >= 0:
            node = downstream[node]
        self.assertEqual(node % 60, 59, "single-pixel depression must not become an invented sea outlet")

    def test_enclosed_water_obeys_game_sea_level_contract(self):
        from preprocess_hydrology import ocean_mask, vector_network

        dem = np.full((24, 24), 100.0, np.float32)
        dem[8:16, 8:16] = -50.0
        water = dem.ravel() <= 0
        self.assertTrue(np.all(ocean_mask(dem)[water]), "enclosed water must not become land drainage")
        downstream, order, area, roots, _ = drainage(dem, 1.0)
        self.assertTrue(np.all(downstream[water] == -1), "rivers end at the first water pixel")
        self.assertAlmostEqual(area[downstream < 0].sum(), np.count_nonzero(~water) * 65536.0 / dem.size)
        reaches, _ = vector_network(dem, 1.0, downstream, order, area, roots)
        for reach in reaches:
            for point in reach["points"][:-1]:
                self.assertGreater(dem[min(int(point[1] * 24), 23), min(int(point[0] * 24), 23)], 0)

    def test_narrow_valley_drains_and_deep_basin_is_retained(self):
        dem = np.full((40, 60), 150.0, np.float32)
        dem[20, :] = np.linspace(80, -1, 60)
        d, order, area, roots, filled = drainage(dem, 1.5)
        start = 20 * 60
        seen = set()
        while d[start] >= 0:
            self.assertNotIn(start, seen)
            seen.add(start)
            start = d[start]
        self.assertLessEqual(dem.ravel()[start], 0)
        self.assertEqual(len(order), dem.size)
        self.assertAlmostEqual(area[d < 0].sum(), (dem > 0).sum() * 1.5 * 65536 / dem.size)
        dem[8:12, 8:12] = 10
        d, _, _, roots, _ = drainage(dem, 1.5)
        self.assertGreater(roots.sum(), 0)
        self.assertTrue(np.any((d.reshape(dem.shape)[8:12, 8:12]) < 0))

    def test_vector_simplification_preserves_junctions(self):
        points = np.array([[0, 0], [1, 0], [1, 1], [2, 1], [2, 2]], float)
        result = simplify(points, 0.71)
        np.testing.assert_array_equal(result[[0, -1]], points[[0, -1]])
        self.assertLess(len(result), len(points))

    def test_incoming_reach_areas_exclude_other_branches_at_junction(self):
        from preprocess_hydrology import vector_network

        # An asymmetric Y: three land cells feed the left incoming reach,
        # two feed the right; the junction contributes its own sixth cell.
        shape = (7, 7)
        dem = np.full(shape, -1.0, np.float32)
        links = {8: 16, 9: 16, 12: 18, 16: 24, 18: 24, 24: 31, 31: 38}
        downstream = np.full(dem.size, -1, np.int32)
        for node, target in links.items():
            dem.ravel()[node] = 100.0
            downstream[node] = target
        chain = [8, 9, 12, 16, 18, 24, 31, 38]
        order = np.array([i for i in range(dem.size) if i not in chain] + chain, np.int32)
        aspect = 1.0
        cell_area = aspect * 65536.0 / dem.size
        area = (dem.ravel() > 0).astype(np.float64) * cell_area
        for node in order:
            if downstream[node] >= 0:
                area[downstream[node]] += area[node]
        roots = np.zeros(dem.size, bool)
        reaches, owner = vector_network(dem, aspect, downstream, order, area, roots)
        junction_uv = [(24 % shape[1] + 0.5) / shape[1], (24 // shape[1] + 0.5) / shape[0]]
        junction = next(reach for reach in reaches if np.allclose(reach["points"][0], junction_uv))
        incoming = [reach for reach in reaches if reach["downstream_id"] == junction["id"]]

        self.assertEqual(len(incoming), 2)
        branch_areas = sorted(reach["catchment_area"] for reach in incoming)
        np.testing.assert_allclose(branch_areas, [area[18], area[16]])
        np.testing.assert_allclose(branch_areas, [2 * cell_area, 3 * cell_area])
        self.assertTrue(all(branch_area < area[24] for branch_area in branch_areas))
        self.assertAlmostEqual(sum(branch_areas) + cell_area, area[24])

        # Sparse climate weights are LOCAL contributing area, not cumulative
        # upstream catchment area. Every land cell must be counted exactly once.
        weights_total = 0.0
        for reach in reaches:
            weights = reach["climate_areas"]
            self.assertEqual(len(weights), len(reach["climate_cells"]))
            self.assertTrue(all(weight > 0 for weight in weights))
            owned_land = np.count_nonzero((owner == reach["id"]) & (dem.ravel() > 0))
            self.assertAlmostEqual(sum(weights), owned_land * cell_area, delta=cell_area * 1e-6)
            weights_total += sum(weights)
        self.assertTrue(np.all(owner[dem.ravel() > 0] >= 0))
        self.assertAlmostEqual(weights_total, np.count_nonzero(dem > 0) * cell_area, delta=cell_area * 1e-6)
        self.assertAlmostEqual(weights_total, area[38], delta=cell_area * 1e-6)


if __name__ == "__main__":
    unittest.main()
