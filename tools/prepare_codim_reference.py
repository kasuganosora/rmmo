"""Prepare a pinned C-IPC checkout for headless Linux reference evaluation.

Does not install system packages, build, or modify the game's physics backend.
Only build-system compatibility changes are applied; shell/contact algorithms
and original license stay unchanged.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

PIN = '9c6cbe3a5bef09a967ca8d420056adfafdf1fc9a'
DEPENDENCIES = {
    'amgcl': 'd34933b02c37ff26b79b4558e31f968a829c4bb0',
    'Cabana': 'c33c8a00b42560129e9953eac0d0f4109624c90d',
    'Kokkos': '7933c2e4b9c83a4d99101acbf2ae06a1115f50d5',
    'Kokkos_kernels': '07a60bcc136d4db46f1a05102762a0a17c07049f',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checkout', type=Path)
    args = parser.parse_args()
    root = args.checkout.resolve()
    head = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    if head != PIN:
        raise ValueError('Unexpected upstream revision: ' + head)
    original = subprocess.check_output(['git', '-C', str(root), 'show', PIN + ':CMakeLists.txt']).decode()
    patched = original.replace('add_subdirectory(Externals/pybind11-master)',
                               '# RMMO: use the local distro package, compatible with Python 3.12.\nfind_package(pybind11 CONFIG REQUIRED)')
    patched = patched.replace('find_package(GLUT REQUIRED)',
                              '# RMMO: no GLUT symbols are used by this headless module.\noption(RMMO_HEADLESS_REFERENCE "Build without the unused display dependency" ON)\nif(NOT RMMO_HEADLESS_REFERENCE)\n  find_package(GLUT REQUIRED)\nendif()')
    path = root / 'CMakeLists.txt'
    if path.read_text(encoding='utf-8') not in (original, patched):
        raise ValueError('Checkout contains other CMake changes; refusing to overwrite them')
    if path.read_text(encoding='utf-8') != patched:
        path.write_text(patched, encoding='utf-8', newline='\n')
    # GCC 13 rejects the old unqualified name preceding a nested alias with
    # the same name. Explicit qualification retains its intended outer alias.
    relative = 'Externals/meta/include/meta/meta.hpp'
    original_meta = subprocess.check_output(['git', '-C', str(root), 'show', PIN + ':' + relative]).decode()
    start = original_meta.index('        struct partition_')
    end = original_meta.index('    } // namespace detail', start)
    patched_meta = original_meta[:start] + original_meta[start:end].replace('invoke<Fn, A>', 'meta::invoke<Fn, A>') + original_meta[end:]
    meta_path = root / relative
    if meta_path.read_text(encoding='utf-8') not in (original_meta, patched_meta):
        raise ValueError('Other meta header changes exist; refusing to overwrite')
    if meta_path.read_text(encoding='utf-8') != patched_meta:
        meta_path.write_text(patched_meta, encoding='utf-8', newline='\n')
    relative = 'Externals/CMakeLists.txt'
    original_deps = subprocess.check_output(['git', '-C', str(root), 'show', PIN + ':' + relative]).decode()
    patched_deps = original_deps.replace('GIT_REPOSITORY https://github.com/ddemidov/amgcl.git',
                                        'GIT_REPOSITORY https://github.com/ddemidov/amgcl.git\n        GIT_TAG ' + DEPENDENCIES['amgcl'])
    patched_deps = patched_deps.replace('GIT_REPOSITORY https://github.com/Liby99/Cabana # Forked to get rid of find_package(Kokkos)',
                                        'GIT_REPOSITORY https://github.com/Liby99/Cabana # Forked to get rid of find_package(Kokkos)\n  GIT_TAG ' + DEPENDENCIES['Cabana'])
    deps_path = root / relative
    if deps_path.read_text(encoding='utf-8') not in (original_deps, patched_deps):
        raise ValueError('Other dependency CMake changes exist; refusing to overwrite')
    if deps_path.read_text(encoding='utf-8') != patched_deps:
        deps_path.write_text(patched_deps, encoding='utf-8', newline='\n')
    relative = 'Library/Math/AMGCL_SOLVER.h'
    original_binding = subprocess.check_output(['git', '-C', str(root), 'show', PIN + ':' + relative]).decode()
    traits = '''// RMMO: ptree is a recursive container; use its actual C++ construction
// traits instead of recursively expanding value_type through itself.
namespace pybind11 { namespace detail {
template <> struct is_copy_constructible<boost::property_tree::ptree>
    : std::is_copy_constructible<boost::property_tree::ptree> {};
template <> struct is_move_constructible<boost::property_tree::ptree>
    : std::is_move_constructible<boost::property_tree::ptree> {};
}}

'''
    patched_binding = original_binding.replace('namespace JGSL {', traits + 'namespace JGSL {', 1)
    binding_path = root / relative
    if binding_path.read_text(encoding='utf-8') not in (original_binding, patched_binding):
        raise ValueError('Other binding changes exist; refusing to overwrite')
    if binding_path.read_text(encoding='utf-8') != patched_binding:
        binding_path.write_text(patched_binding, encoding='utf-8', newline='\n')
    manifest_path = root / 'RMMO_REFERENCE.json'
    previous = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else {}
    if previous and previous.get('revision') != PIN:
        raise ValueError('Existing reference manifest belongs to another revision')
    manifest = dict(previous)
    manifest.update(upstream='https://github.com/ipc-sim/Codim-IPC', revision=PIN,
                    scope='headless reference evaluation, not a Godot backend',
                    cmake_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                    changes=['external pybind11 for Python 3.12', 'optional unused GLUT dependency',
                             'qualify outer meta::invoke for GCC 13', 'pin previously unversioned dependencies',
                             'use actual C++ construction traits for recursive ptree binding'],
                    dependency_revisions=DEPENDENCIES,
                    algorithms_modified=False,
                    patched_files_sha256={str(p.relative_to(root)).replace('\\', '/'):
                                          hashlib.sha256(p.read_bytes()).hexdigest()
                                          for p in [path, meta_path, deps_path, binding_path]})
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps(manifest))


if __name__ == '__main__':
    main()
