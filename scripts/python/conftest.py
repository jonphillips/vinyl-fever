"""Make the sibling scripts importable from the tests regardless of where
pytest is invoked (the tests do `from rule_scrub_tags import ...`)."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
