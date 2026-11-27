import ast
import unittest

from services.agent import checks


def names(source: str) -> list[str]:
    return checks.undefined_log_names(ast.parse(source))


class UndefinedLogNames(unittest.TestCase):
    def test_logger_without_definition_is_reported(self):
        src = "def f(x):\n    try:\n        return int(x)\n    except ValueError as exc:\n        logger.error('bad %s', exc)\n"
        self.assertEqual(names(src), ["logger"])

    def test_defined_logger_passes(self):
        src = "import logging\nlogger = logging.getLogger(__name__)\n\ndef f():\n    logger.info('x')\n"
        self.assertEqual(names(src), [])

    def test_logging_module_used_without_import_is_reported(self):
        self.assertEqual(names("def f():\n    logging.warning('x')\n"), ["logging"])

    def test_imported_logger_passes(self):
        self.assertEqual(names("from common import logger\n\ndef f():\n    logger.info('x')\n"), [])

    def test_argument_and_local_names_count_as_defined(self):
        self.assertEqual(names("def f(logger):\n    logger.info('x')\n"), [])
        self.assertEqual(names("def f():\n    logger = make()\n    logger.info('x')\n"), [])

    def test_star_import_is_not_judged(self):
        self.assertEqual(names("from helpers import *\n\ndef f():\n    logger.info('x')\n"), [])

    def test_precheck_blocks_the_commit_with_a_clear_message(self):
        files = [{"path": "bot/utils/uuid_helpers.py", "content": "def f():\n    logger.error('x')\n"}]
        message = checks.precheck(files)
        self.assertIn("logger", message)
        self.assertIn("NameError", message)

    def test_precheck_allows_a_file_with_its_own_logger(self):
        files = [{"path": "bot/utils/ok.py", "content": "import logging\nlogger = logging.getLogger(__name__)\nlogger.info('x')\n"}]
        self.assertIsNone(checks.precheck(files))


if __name__ == "__main__":
    unittest.main()
