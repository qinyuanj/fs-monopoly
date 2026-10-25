"""Resolve exactly the same scoped mutation files as the upstream dispatcher (#93).

Imports the adjacent uml-viewer's own scope
adapter instead of re-implementing selection here. Writes the JSON target list
that mutation_evidence.py consumes.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))


def main(root_text, tool_root_text, args_file, out_file):
    root = Path(root_text).resolve()
    scripts = Path(tool_root_text).resolve() / 'scripts'
    sys.path.insert(0, str(scripts))
    from uml_quality import read_config, scope, targets

    config = read_config(root)
    if not config or 'standardTools' not in config or 'operations' in config:
        raise ValueError('Independent mutation verification requires standardTools.')
    forward = json.loads(Path(args_file).read_text(encoding='utf-8-sig'))
    standard = config['standardTools']
    roots = scope(root, standard)
    # Empty forward means "the declared business roots", same as the upstream
    # PowerShell adapter's default target set.
    named = forward if forward else list(standard.get('sourceRoots', []))
    _options, files = targets(root, named, roots, standard.get('exclude', []))
    Path(out_file).write_text(json.dumps(files, ensure_ascii=False), encoding='utf-8')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main(*sys.argv[1:5]))
    except (OSError, ValueError, KeyError) as error:
        print(f'mutation target selection: {error}', file=sys.stderr)
        sys.exit(1)
