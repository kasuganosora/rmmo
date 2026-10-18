#!/usr/bin/env python3
"""Contract checks for facade generation and the matching real-server fence."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import generate_mock_server_api as facade
import generate_remote_boundary as boundary


class GenerationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="rmmo-api-test-")
        self.root = Path(self.temporary.name)
        self.modules = self.root / "scripts/net/server"
        self.modules.mkdir(parents=True)
        self.root_patch = patch.object(facade, "ROOT", self.root)
        self.root_patch.start()

    def tearDown(self):
        self.root_patch.stop()
        self.temporary.cleanup()

    def source(self, name, text):
        (self.modules / (name + "_module.gd")).write_text(text)

    def test_arguments_keep_nested_defaults_and_string_contents(self):
        self.source("sample", '''## @server-api
func try_move(cell: Vector2i = Vector2i(-1, -1),
              tags: Array = ["a,  b", "x"], count: int = 2) -> Dictionary:
    return {}
''')
        generated = facade.generate()
        self.assertIn('tags: Array = ["a,  b", "x"]', generated)
        self.assertIn('_sample_module_logic.try_move(cell, tags, count)', generated)

    def test_state_uses_write_through_properties(self):
        self.source("sample", '''## @server-state
var members: Array[Dictionary] = []
## @server-state
var serial := 0
''')
        generated = facade.generate()
        self.assertIn('var members: Array[Dictionary]:', generated)
        self.assertIn('get: return _sample_module_logic.members', generated)
        self.assertIn('set(value): _sample_module_logic.members = value', generated)
        self.assertNotIn('duplicate', generated)

    def test_aliases_export_only_marked_methods(self):
        self.source("sample", '''## @server-api try_expression
func request(weights: Dictionary) -> Dictionary:
    return {}
func helper() -> void:
    pass
''')
        generated = facade.generate()
        self.assertIn('func try_expression(weights: Dictionary)', generated)
        self.assertIn('_sample_module_logic.request(weights)', generated)
        self.assertNotIn('func helper', generated)

    def test_duplicate_exports_fail(self):
        for name in ['one', 'two']:
            self.source(name, '## @server-state\nvar shared: Dictionary = {}\n')
        with self.assertRaisesRegex(ValueError, 'Duplicate server export: shared'):
            facade.generate()

    def test_misplaced_annotations_fail(self):
        self.source('sample', '## @server-state\nfunc wrong() -> void:\n    pass\n')
        with self.assertRaisesRegex(ValueError, 'must precede a var'):
            facade.generate()

    def test_real_boundary_fences_new_requests_and_snapshots(self):
        self.source('sample', '''## @server-api
func try_buy(item: String) -> Dictionary:
    return {}
## @server-api
func snapshot_items() -> Array[Dictionary]:
    return []
## @server-api
func snapshot_self() -> Dictionary:
    return {}
## @server-api
func try_command() -> void:
    pass
## @server-api
func try_flag() -> bool:
    return true
''')
        generated = boundary.generate()
        self.assertIn('return _unsupported("try_buy")', generated)
        self.assertIn('func snapshot_items() -> Array[Dictionary]:\n\treturn []', generated)
        self.assertIn('func snapshot_self() -> Dictionary:\n\treturn {}', generated)
        self.assertIn('_remote_notice("try_command")', generated)
        self.assertIn('_remote_notice("try_flag")\n\treturn false', generated)
        self.assertNotIn('_sample_module_logic', generated)


if __name__ == '__main__':
    unittest.main()
