"""Compare retained Traditional artifact with candidate across development cells."""
import concurrent.futures
import hashlib
import itertools
import json
import pathlib
import subprocess
import sys

candidate_root = pathlib.Path(sys.argv[1])
anchor_binary = pathlib.Path(sys.argv[2])
anchor_manifest = json.loads((anchor_binary.parent / 'provenance.json').read_text())
assert hashlib.sha256(anchor_binary.read_bytes()).hexdigest() == anchor_manifest['sha256']
output = candidate_root.parent / 'traditional-invariance'
output.mkdir(exist_ok=True)
cells = itertools.product(['archipelago', 'peninsula', 'twinIslands'], ['on', 'off'], ['on', 'off'])
jobs = [(cell, family, fog, wild, players) for cell, (family, fog, wild) in enumerate(cells) for players in [3, 4]]


def run(job):
    cell, family, fog, wild, players = job
    name = f'{cell}-{players}-traditional-0'
    command = [str(anchor_binary), '--games', '1', '--seed', str(700000+cell*100), '--players', str(players), '--family', family, '--fog', fog, '--wild', wild, '--seats', ','.join(['traditional']*players), '--build-id', anchor_manifest['sourceCommit'], '--arm', 'traditional', '--focal-chair', '0']
    with (output/(name+'.jsonl')).open('w') as stdout, (output/(name+'.timing')).open('w') as stderr:
        result = subprocess.run(command, stdout=stdout, stderr=stderr)
    assert result.returncode == 0, (name, result.returncode)
    anchor = json.loads((output/(name+'.jsonl')).read_text())
    candidate = json.loads((candidate_root/(name+'.jsonl')).read_text())
    anchor.pop('buildID')
    candidate.pop('buildID')
    assert anchor == candidate, name
    return {'cell':cell, 'players':players, 'fingerprint':anchor['fingerprint'], 'identical':True}


with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    results = list(pool.map(run, jobs))
(output/'results.json').write_text(json.dumps(results, indent=2)+'\n')
print(json.dumps({'configurations':len(results), 'allIdentical':all(r['identical'] for r in results)}))
