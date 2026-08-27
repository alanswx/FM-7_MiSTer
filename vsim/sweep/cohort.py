#!/usr/bin/env python3
"""Draw the next cohort of disks to sweep, excluding everything already covered.

The collection is too large to sweep end-to-end on every change: the reference
side is minutes, but our side is roughly a day at 12 jobs. Sweeping a random
cohort at a time gives the same coverage incrementally, with a bounded run each
time, and keeps every cohort's disk list on disk so coverage is a fact rather
than a recollection.

    cohort.py status                  # coverage so far
    cohort.py next  [--size 40]       # draw a cohort, write cohorts/NN-images.txt
    cohort.py retire NN <outdir>      # mark NN covered -- ONLY if it really is
    cohort.py all   <outdir>          # the final pass: every disk, one list

RETIRE IS THE PART THAT MATTERS. A cohort is covered when *our* side rendered
every disk in it, not when it was drawn. A sweep that returns 37 shots for 40
disks and is retired anyway buries three disks permanently, and nothing later
looks for them -- the coverage count says 40. `retire` recounts against the
outdir and refuses if any disk is missing a shot.

POPULATION. Disks are deduplicated BY CONTENT, not by name: the collection
carries the same image under several paths (663 FM-7 files, 401 distinct). Name
collisions are excluded and listed in cohorts/excluded-name-collisions.txt
rather than dropped silently -- see trap 68 in docs/REFERENCE.md, where two
different disks can otherwise share one row and the two machines can render
different disks under one verdict.
"""
import hashlib
import os
import random
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
COHORTS = os.path.join(HERE, 'cohorts')
KEEP = set('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-')


def safe_name(path):
    """The sweep's own rule, from sweep_one.sh:9 -- and note `tr -c` converts the
    trailing NEWLINE too, which is where the trailing '_' comes from."""
    b = os.path.basename(path)
    # `basename "$img" .d77` strips the suffix CASE-SENSITIVELY, so a disk named
    # FOO.D77 keeps its extension and its safe name is FOO.D77_ , not FOO_.
    # Stripping case-insensitively here matches 33 of 40 names and silently
    # misses the rest.
    if b.endswith('.d77'):
        b = b[:-4]
    return ''.join(c if c in KEEP else '_' for c in b) + '_'


def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def hash_cache():
    """Hashing the collection takes a few seconds; cache it by (path, size, mtime)."""
    cache_path = os.path.join(COHORTS, '.hashes.tsv')
    cache = {}
    if os.path.exists(cache_path):
        for ln in open(cache_path):
            f = ln.rstrip('\n').split('\t')
            if len(f) == 4:
                cache[f[0]] = (f[1], f[2], f[3])
    return cache_path, cache


def population(machine='fm7'):
    """Every distinct disk, one canonical path each."""
    out = subprocess.run(['find', os.path.join(REPO, 'software'), '-iname', '*.d77'],
                         capture_output=True, text=True).stdout.split('\n')
    paths = [p for p in out if p]
    # FM77AV titles need the initiator ROM and the AV memory map; they will not
    # boot as an FM-7 and both machines would render them blank.
    if machine == 'fm7':
        paths = [p for p in paths if '(FM77AV)' not in p]
    else:
        paths = [p for p in paths if '(FM77AV)' in p]

    cache_path, cache = hash_cache()
    by_hash, fresh = {}, {}
    for p in sorted(paths):
        st = os.stat(p)
        key, sig = p, (str(st.st_size), str(int(st.st_mtime)))
        c = cache.get(key)
        h = c[0] if c and (c[1], c[2]) == sig else md5(p)
        fresh[key] = (h, sig[0], sig[1])
        # prefer the shortest path so the flat D77/ copy wins over a per-title dir
        if h not in by_hash or len(p) < len(by_hash[h]):
            by_hash[h] = p
    os.makedirs(COHORTS, exist_ok=True)
    with open(cache_path, 'w') as f:
        for k, v in sorted(fresh.items()):
            f.write('\t'.join((k,) + v) + '\n')

    # Exclude safe-name collisions and SAY which, so coverage stays honest.
    counts = {}
    for h, p in by_hash.items():
        counts[safe_name(p)] = counts.get(safe_name(p), 0) + 1
    clean = {h: p for h, p in by_hash.items() if counts[safe_name(p)] == 1}
    dropped = sorted(p for h, p in by_hash.items() if counts[safe_name(p)] > 1)
    if dropped:
        with open(os.path.join(COHORTS, 'excluded-name-collisions.txt'), 'w') as f:
            f.write('# Distinct disks sharing a safe-name with another disk.\n'
                    '# The sweep would merge them into one row and the two machines\n'
                    '# could render different disks under one verdict -- trap 68.\n'
                    '# Sweeping these needs sweep_one.sh to disambiguate the name.\n')
            for p in dropped:
                f.write(os.path.relpath(p, REPO) + '\n')
    return clean, dropped


def covered_hashes():
    """Hashes retired by a previous cohort. Only .retired files count."""
    done = set()
    if not os.path.isdir(COHORTS):
        return done
    for n in sorted(os.listdir(COHORTS)):
        if n.endswith('-images.retired'):
            for ln in open(os.path.join(COHORTS, n)):
                ln = ln.strip()
                if ln and not ln.startswith('#'):
                    done.add(ln.split('\t')[0])
    return done


def write_list(path, items):
    with open(path, 'w') as f:
        for h, p in items:
            f.write(f'{h}\t{p}\n')


def cmd_status(machine):
    pop, dropped = population(machine)
    done = covered_hashes()
    n_done = len(done & set(pop))
    pend = [n for n in sorted(os.listdir(COHORTS))
            if n.endswith('-images.txt') and not os.path.exists(
                os.path.join(COHORTS, n.replace('-images.txt', '-images.retired')))]
    print(f'machine        : {machine}')
    print(f'distinct disks : {len(pop)}  (+{len(dropped)} excluded, name collisions)')
    print(f'covered        : {n_done}  ({100.0 * n_done / max(1, len(pop)):.1f}%)')
    print(f'remaining      : {len(pop) - n_done}')
    if pend:
        print(f'cohorts drawn but NOT retired: {", ".join(pend)}')
    return 0


def cmd_next(machine, size):
    pop, _ = population(machine)
    done = covered_hashes()
    avail = sorted((h, p) for h, p in pop.items() if h not in done)
    if not avail:
        print('every distinct disk is covered -- run `cohort.py all <outdir>` for the '
              'full validation pass')
        return 1
    nums = [int(n[:2]) for n in os.listdir(COHORTS) if n.endswith('-images.txt')]
    n = max(nums) + 1 if nums else 1
    # Seed from the cohort number alone, so a cohort is reproducible from its
    # number and the retired set, with no hidden state.
    random.seed(f'{machine}-cohort-{n}')
    take = sorted(random.sample(avail, min(size, len(avail))))
    assert len({safe_name(p) for _, p in take}) == len(take), 'safe-name collision'
    out = os.path.join(COHORTS, f'{n:02d}-images.txt')
    write_list(out, take)
    plain = os.path.join(COHORTS, f'{n:02d}-images.paths')
    with open(plain, 'w') as f:
        for _, p in take:
            f.write(p + '\n')
    print(f'cohort {n:02d}: {len(take)} disks of {len(avail)} remaining -> {out}')
    print(f'  cp {plain} <outdir>/images.txt')
    print(f'  MACHINE={machine} ./sweep-list.sh <outdir> 8 2000')
    print(f'  ./ref-shots-at-frame.sh <outdir> 1980 6 {machine}')
    print(f'  python3 compare-ref.py <outdir>')
    print(f'  python3 cohort.py retire {n} <outdir>')
    return 0


def cmd_retire(n, outdir):
    src = os.path.join(COHORTS, f'{int(n):02d}-images.txt')
    if not os.path.exists(src):
        print(f'no such cohort: {src}', file=sys.stderr)
        return 2
    items = [ln.rstrip('\n').split('\t') for ln in open(src) if ln.strip()]
    shots = os.path.join(outdir, 'shots')
    # One rule, not two. A second "just in case" spelling here would have hidden
    # the case-sensitivity bug in safe_name(): it matched 33 of 40 and the
    # fallback made the total look plausible.
    missing = [p for _, p in items
               if not os.path.exists(os.path.join(shots, safe_name(p) + '.png'))]
    if missing:
        print(f'REFUSING to retire cohort {int(n):02d}: {len(missing)} of {len(items)} '
              f'disks have no render from OUR side.', file=sys.stderr)
        print('A cohort is covered when our side rendered every disk in it, not when '
              'it was drawn. Retiring now buries these permanently:', file=sys.stderr)
        for p in missing[:10]:
            print('    ' + os.path.basename(p), file=sys.stderr)
        if len(missing) > 10:
            print(f'    ... and {len(missing) - 10} more', file=sys.stderr)
        return 1
    dst = src.replace('-images.txt', '-images.retired')
    os.rename(src, dst)
    print(f'cohort {int(n):02d} retired: {len(items)} disks -> {dst}')
    return 0


def cmd_all(machine, outdir):
    pop, dropped = population(machine)
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, 'images.txt'), 'w') as f:
        for h, p in sorted(pop.items(), key=lambda kv: kv[1]):
            f.write(p + '\n')
    print(f'{len(pop)} distinct disks -> {outdir}/images.txt')
    if dropped:
        print(f'{len(dropped)} excluded for name collisions -- see '
              f'cohorts/excluded-name-collisions.txt')
    return 0


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return 2
    machine = 'fm7'
    if '--machine' in a:
        machine = a[a.index('--machine') + 1]
    size = 40
    if '--size' in a:
        size = int(a[a.index('--size') + 1])
    os.makedirs(COHORTS, exist_ok=True)
    if a[0] == 'status':
        return cmd_status(machine)
    if a[0] == 'next':
        return cmd_next(machine, size)
    if a[0] == 'retire':
        return cmd_retire(a[1], a[2])
    if a[0] == 'all':
        return cmd_all(machine, a[1])
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main())
