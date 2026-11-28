import unittest
from services import points

class PointsExtendedTests(unittest.TestCase):
    def test_error_text(self):
        self.assertEqual(points.error_text('USER_NOT_FOUND'), 'Ваш профиль не найден. Напишите @username или ник в игре, а затем нажмите /start.')
        self.assertEqual(points.error_text('INVALID_AMOUNT'), 'Сумма — целое число от 1 до 100 000.')
        self.assertEqual(points.error_text('UNKNOWN'), 'Не получилось. Попробуй позже.')

    def test_has_error(self):
        class MockErr(Exception):
            def __str__(self):
                return 'USER_NOT_FOUND: some message'
        err = MockErr()
        self.assertTrue(points.has_error(err, 'USER_NOT_FOUND'))
        self.assertFalse(points.has_error(err, 'OTHER'))

    def test_fee_label(self):
        row = {'entry_fee_pp': '10'}
        self.assertEqual(points.fee_label(row), '10 PP')
        row = {'entry_fee_pp': '0'}
        self.assertEqual(points.fee_label(row), 'бесплатно')
        row = {'entry_fee_pp': '1000'}
        self.assertEqual(points.fee_label(row), '1 000 PP')
        row = {'entry_fee_pp': 'abc'}
        self.assertEqual(points.fee_label(row), '0 PP')

    def test_fmt(self):
        self.assertEqual(points.fmt(1000), '1 000')
        self.assertEqual(points.fmt(0), '0')
        self.assertEqual(points.fmt(123456), '123 456')
        self.assertEqual(points.fmt(-50), '50')
        self.assertEqual(points.fmt('abc'), '0')
