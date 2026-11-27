from services import quiz
import unittest

class QuizParseTests(unittest.TestCase):
    def test_parse_valid_quiz(self):
        quiz_data = '{"question": "Какой цвет трава?", "options": ["Зеленый", "Синий", "Красный", "Желтый"], "correct": 0, "explanation": "Трава зеленая"}'
        result = quiz.parse(quiz_data)
        self.assertEqual(result["question"], "Какой цвет трава?")
        self.assertEqual(result["options"], ["Зеленый", "Синий", "Красный", "Желтый"])
        self.assertEqual(result["correct"], 0)

if __name__ == '__main__':
    unittest.main()