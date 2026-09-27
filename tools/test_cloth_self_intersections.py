import unittest
import numpy as np
from audit_cloth_self_intersections import intersections, compare


class SelfIntersectionTests(unittest.TestCase):
    def test_crossing_and_scale(self):
        points = np.array([[-1,0,-1],[1,0,-1],[0,0,1], [0,-1,0],[0,1,0],[.5,0,0]])
        faces = [[0,1,2],[3,4,5]]
        for scale in [.01,1,100]:
            crossing, planar, bad = intersections(points*scale, faces)
            self.assertEqual(set(crossing), {(0,1)})
            self.assertAlmostEqual(crossing[(0,1)], .5*scale)
            self.assertFalse(planar or bad)
        moved = points.copy(); moved[3:,0] += 3
        baseline = intersections(moved, faces)
        self.assertFalse(baseline[0])
        self.assertEqual(compare(points, faces, baseline)['new_crossing_pairs'], 1)

    def test_adjacency_and_coplanar(self):
        points = [[0,0,0],[1,0,0],[0,1,0],[1,1,0]]
        self.assertFalse(intersections(points, [[0,1,2],[1,3,2]])[0])
        overlapping = points[:3]+[[.1,.1,0],[.8,.1,0],[.1,.8,0]]
        crossing, planar, _ = intersections(overlapping, [[0,1,2],[3,4,5]])
        self.assertFalse(crossing)
        self.assertEqual(planar, [(0,1)])

    def test_invalid(self):
        self.assertEqual(intersections([[0,0,0],[1,0,0],[2,0,0]], [[0,1,2]])[2], [0])
        with self.assertRaises(ValueError):
            intersections([[np.nan,0,0],[1,0,0],[0,1,0]], [[0,1,2]])


if __name__ == '__main__': unittest.main()
