"""uml-quality.json probe for #93 (POSIX form of probe_config.ps1).

Validates the repository config with the adjacent uml-viewer's own reader and
scope adapter (no local re-implementation), then prints the dispatch branch the
upstream dispatcher would take. Read-only: no tool is started, nothing written.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))


def main(root_text, tool_root_text):
    root = Path(root_text).resolve()
    scripts = Path(tool_root_text).resolve() / 'scripts'
    sys.path.insert(0, str(scripts))
    from uml_quality import read_config, scope, targets

    config = read_config(root)
    if not config:
        raise ValueError(f'uml-quality.json is missing under {root}')
    if 'operations' in config:
        raise ValueError('operations is declared; the uml entry supports standardTools only.')
    if 'standardTools' not in config:
        raise ValueError('standardTools is required.')
    if (root / 'deps.edn').exists():
        print('note=deps.edn present; standardTools still wins')
    print('dispatch=standardTools')
    standard = config['standardTools']
    roots = scope(root, standard)
    for path in roots:
        print(f'sourceRoot={path}')
    extra, files = targets(root, list(standard.get('sourceRoots', [])), roots, standard.get('exclude', []))
    print(f'mutateTargets={len(files)}')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1], sys.argv[2]))
    except (OSError, ValueError, KeyError) as error:
        print(f'uml-quality.json: {error}', file=sys.stderr)
        sys.exit(1)
