#!/usr/bin/env python3
"""Run asset-free MockServer domain regressions with the real autoload facade."""
from test_network_regressions import run_tests

TESTS = [(name + '.gd', '_run') for name in (
    'test_mock_server_modules', 'test_party_stub', 'test_party_loot',
    'test_combat_hit_crit', 'test_remote_patrol', 'test_shell_remotes',
)]

if __name__ == '__main__':
    run_tests(TESTS)
