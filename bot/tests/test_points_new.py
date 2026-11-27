from services import points
import unittest

class PointsTextTests(unittest.TestCase):
    def test_parse_amount(self):
        self.assertEqual(points.parse_amount("50"), 50)
        self.assertEqual(points.parse_amount("+100"), 100)
        self.assertEqual(points.parse_amount("-50"), -50)

if __name__ == '__main__':
    unittest.main()