import concurrent.futures
import itertools
import hashlib
import json
import pathlib
import subprocess
import sys
import time

binary, build_id, stage = sys.argv[1:4]
anchor_binary, anchor_id = sys.argv[4:6] if len(sys.argv) >= 6 else (binary, build_id)
anchor_provenance = json.loads((pathlib.Path(anchor_binary).parent / 'provenance.json').read_text())
assert anchor_provenance['sourceCommit'] == anchor_id, 'mistyped anchor source label'
assert hashlib.sha256(pathlib.Path(anchor_binary).read_bytes()).hexdigest() == anchor_provenance['sha256'], 'anchor artifact changed'
provenance = json.loads((pathlib.Path(binary).parent / 'provenance.json').read_text())
assert provenance['sourceCommit'] == build_id, 'mistyped source label'
assert hashlib.sha256(pathlib.Path(binary).read_bytes()).hexdigest() == provenance['sha256'], 'artifact changed'
root = pathlib.Path('/tmp/naval-ai-evidence') / build_id[:7] / stage
root.mkdir(parents=True, exist_ok=True)
families = ['archipelago', 'peninsula', 'twinIslands']
cells = list(itertools.product(families, ['on', 'off'], ['on', 'off']))
jobs = []
for cell, (family, fog, wild) in enumerate(cells):
    for players in [3, 4]:
        if stage == 'matrix':
            entries = [(tier, 0, [tier] * players, 700000 + cell * 100, 1) for tier in ['traditional', 'expert']]
        elif stage == 'mixed-development':
            entries = [('expert', chair, ['expert' if s == chair else 'traditional' for s in range(players)], 700001 + cell * 100, 1) for chair in range(players)]
        elif stage == 'land-development':
            entries = [('land-control', chair, ['land-control' if s == chair else 'traditional' for s in range(players)], 700003 + cell * 100, 1) for chair in range(players)]
        elif stage == 'held-out':
            entries = [(arm, chair, ['expert' if arm == 'candidate' and s == chair else 'traditional' for s in range(players)], 800000 + cell * 1000, 11 if players == 3 else 7) for arm in ['candidate', 'control'] for chair in range(players)]
        else:
            raise ValueError(stage)
        for arm, chair, seats, seed, games in entries:
            name = f'{cell}-{players}-{arm}-{chair}'
            job_binary, job_source = (anchor_binary, anchor_id) if stage == 'held-out' and arm == 'control' else (binary, build_id)
            command = [job_binary, '--games', str(games), '--seed', str(seed), '--players', str(players), '--family', family, '--fog', fog, '--wild', wild, '--seats', ','.join(seats), '--build-id', job_source, '--arm', arm, '--focal-chair', str(chair)]
            jobs.append((name, command))
(root / 'comparison.json').write_text(json.dumps(dict(candidateSource=build_id, candidateSHA256=provenance['sha256'], anchorSource=anchor_id, anchorSHA256=anchor_provenance['sha256'], engineOriginalCommit=provenance['engineOriginalCommit']), indent=2)+'\n')
(root / 'commands.json').write_text(json.dumps(jobs, indent=2) + '\n')

def run(job):
    name, command = job
    out, err = root / (name + '.jsonl'), root / (name + '.timing')
    start = time.monotonic()
    with out.open('w') as stdout, err.open('w') as stderr:
        result = subprocess.run(command, stdout=stdout, stderr=stderr)
    elapsed = time.monotonic() - start
    rows = [json.loads(line) for line in out.read_text().splitlines() if line]
    rejects = sum(bool(row['winner'] is None or row['forcedEnds'] or row['idleSailingCycles'] or row['tradeCycles'] or row['duplicateProposals']) for row in rows)
    return dict(name=name, returncode=result.returncode, games=len(rows), rejects=rejects, seconds=round(elapsed, 3))

start = time.monotonic()
results = []
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    for result in pool.map(run, jobs):
        results.append(result)
        print(json.dumps(result), flush=True)
        (root / 'jobs.json').write_text(json.dumps(results, indent=2) + '\n')
print(json.dumps(dict(stage=stage, jobs=len(jobs), games=sum(r['games'] for r in results), rejects=sum(r['rejects'] for r in results), seconds=time.monotonic()-start)), flush=True)
