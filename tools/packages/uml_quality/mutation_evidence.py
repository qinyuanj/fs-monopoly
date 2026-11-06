"""Independent result verification for the repository's Lua mutation entry (#120).

Only EDN syntax comes from mutator; its validResult and aggregate report are
never trusted. Keep prior artifacts in place for incremental mutation history.
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

from mutator.edn import loads


def snapshot(root, target):
    if not target.endswith('.lua'):
        raise ValueError(f'unsupported mutation target: {target}')
    namespace = target
    for prefix in ('src/lua/', 'src/', 'lua/'):
        if namespace.startswith(prefix):
            namespace = namespace[len(prefix):]
            break
    namespace = namespace[:-4]
    if namespace.endswith('/init'):
        namespace = namespace[:-5]
    namespace = namespace.replace('/', '.')
    return root / '.metrics' / 'mutate' / (namespace + '.edn'), namespace


def identity(path):
    if not path.exists():
        return None
    stat = path.stat()
    return [stat.st_mtime_ns, stat.st_ctime_ns, stat.st_ino,
            hashlib.sha256(path.read_bytes()).hexdigest()]


def prepare(root, targets):
    found = []
    for target in expand_changed(root, targets):
        path, _ = snapshot(root, target)
        found.append({'target': target, 'prior': identity(path)})
    return found


def expand_changed(root, targets):
    """--changed resolves through mutator's own selection, so the evidence set is mutator's set."""
    if targets != ['--changed']:
        return targets
    from mutator.cli import parse_args, select_files
    config = json.loads((root / 'uml-quality.json').read_text(encoding='utf-8-sig'))
    standard = config['standardTools']
    argv = ['--root', str(root), '--changed']
    for source_root in standard.get('sourceRoots', []):
        argv += ['--source-root', source_root]
    for pattern in standard.get('exclude', []):
        argv += ['--exclude', pattern]
    files = [path.relative_to(root).as_posix() for path in select_files(parse_args(argv))]
    if not files:
        raise ValueError('--changed selected no source files')
    return files


def no_sites(root, target):
    from mutator.crapper_link import ensure_crapper
    ensure_crapper()
    from crapper.languages.treesitter import parse
    _data, tree = parse((root / target).read_text(encoding='utf-8'), 'lua')
    if tree.root_node.has_error:
        return False
    result = subprocess.run(
        [sys.executable, '-I', '-m', 'mutator', '--scan', '--no-coverage', target],
        cwd=root, capture_output=True, text=True, check=False,
    )
    expected = f'Scan: 0 mutation sites in {target}'
    return result.returncode == 0 and result.stdout.strip() == expected


def counts(data, target, namespace):
    if not isinstance(data, dict) or data.get('version') != 1:
        raise ValueError('invalid snapshot')
    if data.get('source') != target or data.get('namespace') != namespace:
        raise ValueError('snapshot belongs to another target')
    forms = data.get('forms')
    if not isinstance(forms, list) or not forms:
        raise ValueError('snapshot has no statistics')
    totals = [0, 0, 0, 0]
    for form in forms:
        if not isinstance(form, dict) or form.get('file') != target:
            raise ValueError('form belongs to another target')
        values = [form.get(key) for key in ('sites', 'killed', 'survived', 'uncovered')]
        if any(type(value) is not int or value < 0 for value in values):
            raise ValueError('invalid mutation statistics')
        # --lines omits covered but unselected sites from outcome counts.
        if values[0] < sum(values[1:]):
            raise ValueError('inconsistent mutation statistics')
        totals = [a + b for a, b in zip(totals, values)]
    return totals


def verify(root, entries):
    failed = False
    for entry in entries:
        target = entry['target']
        try:
            path, namespace = snapshot(root, target)
            current = identity(path)
            if current is None:
                if no_sites(root, target):
                    print(f'uml: mutation status=no-sites target={target} mutations=0 killed=0 survived=0')
                    continue
                raise ValueError('snapshot missing; target has sites or scan did not prove no-sites')
            if current == entry['prior']:
                raise ValueError('snapshot is not from this run')
            sites, killed, survived, uncovered = counts(loads(path.read_text(encoding='utf-8')), target, namespace)
            if sites == 0:
                if not no_sites(root, target):
                    raise ValueError('zero statistics without a successful no-sites scan')
                print(f'uml: mutation status=no-sites target={target} mutations=0 killed=0 survived=0')
            else:
                if killed + survived == 0:
                    raise ValueError('snapshot has no executed mutations')
                print(f'uml: mutation status=valid target={target} mutations={sites} killed={killed} survived={survived} uncovered={uncovered}')
        except (OSError, ValueError, TypeError, KeyError) as error:
            failed = True
            print(f'uml: mutation status=not-executed target={target}: {error}')
    return 1 if failed or not entries else 0


def main():
    phase, root_text, targets_file, manifest_file = sys.argv[1:]
    root = Path(root_text).resolve()
    manifest = Path(manifest_file)
    if phase == 'prepare':
        targets = json.loads(Path(targets_file).read_text(encoding='utf-8-sig'))
        if not isinstance(targets, list) or not targets:
            raise ValueError('no mutation targets selected')
        manifest.write_text(json.dumps(prepare(root, targets)), encoding='utf-8')
        return 0
    return verify(root, json.loads(manifest.read_text(encoding='utf-8')))


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f'uml: mutation evidence failed: {error}', file=sys.stderr)
        sys.exit(1)
