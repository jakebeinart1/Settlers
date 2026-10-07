import collections
import json
import math
import pathlib
import random
import re
import statistics
import sys

root = pathlib.Path(sys.argv[1])
comparison = json.loads((root/'comparison.json').read_text()) if (root/'comparison.json').exists() else None
rows = [json.loads(line) for file in sorted(root.glob('*.jsonl')) for line in file.read_text().splitlines() if line]

def wilson(wins, count):
    if not count: return None
    z = 1.959963984540054
    p = wins / count
    denom = 1 + z*z/count
    center = (p + z*z/(2*count)) / denom
    margin = z * math.sqrt(p*(1-p)/count + z*z/(4*count*count)) / denom
    return [round(center-margin, 6), round(center+margin, 6)]

def summary(data):
    complete = [r for r in data if r['winner'] is not None]
    focal_wins = sum(r['winner'] == r['focalChair'] for r in complete)
    totals = {key: sum(sum(s[key] for s in r['behavior']) for r in data) for key in data[0]['behavior'][0]} if data else {}
    focal = {key: sum(r['behavior'][r['focalChair']][key] for r in data) for key in data[0]['behavior'][0]} if data else {}
    return dict(games=len(data), complete=len(complete), completionCI=wilson(len(complete),len(data)), focalWins=focal_wins,
                focalWinRate=focal_wins/len(complete) if complete else None, focalWinCI=wilson(focal_wins,len(complete)),
                forced=sum(r['forcedEnds'] for r in data), sailingCycles=sum(r['sailingCycles'] for r in data), idleSailingCycles=sum(r.get('idleSailingCycles',r['sailingCycles']) for r in data), tradeCycles=sum(r['tradeCycles'] for r in data), duplicates=sum(r['duplicateProposals'] for r in data),
                movesMin=min((r['moves'] for r in data),default=None), movesMax=max((r['moves'] for r in data),default=None),
                gamesWithShips=sum(any(s['shipsBought'] for s in r['behavior']) for r in data), gamesWithColonies=sum(any(s['colonies'] for s in r['behavior']) for r in data),
                totals=totals,focalTotals=focal)

jobs = json.loads((root/'jobs.json').read_text()) if (root/'jobs.json').exists() else None
if jobs is not None:
    assert all(job['returncode']==0 for job in jobs), 'failed simulation process'
    assert sum(job['games'] for job in jobs)==len(rows), 'missing simulation rows'
report = {'functionalGatePassed': bool(rows) and sum(r['winner'] is not None for r in rows)/len(rows)>=.99 and not any(r['forcedEnds'] or r.get('idleSailingCycles',r['sailingCycles']) or r['tradeCycles'] or r['duplicateProposals'] for r in rows), 'comparison': comparison, 'sourceIDs': sorted(set(r['buildID'] for r in rows)), 'games': len(rows), 'byTable': {}}
for players in [3,4]:
    table = [r for r in rows if r['playerCount'] == players]
    arms = sorted(set(r['arm'] for r in table))
    entry = dict(overall=summary(table), arms={arm:summary([r for r in table if r['arm']==arm]) for arm in arms})
    entry['chairs'] = {arm:{chair:summary([r for r in table if r['arm']==arm and r['focalChair']==chair]) for chair in range(players)} for arm in arms}
    entry['cells'] = {'/'.join(map(str,key)):summary(data) for key,data in sorted({key:[r for r in table if (r['family'],r['fogEnabled'],r['resourceChoiceEnabled'],r['arm'])==key] for key in set((r['family'],r['fogEnabled'],r['resourceChoiceEnabled'],r['arm']) for r in table)}.items())}
    if set(arms)=={'candidate','control'}:
        keyed = {(r['family'],r['fogEnabled'],r['resourceChoiceEnabled'],r['seed'],r['focalChair'],r['arm']):r for r in table}
        assert len(keyed)==len(table), 'duplicate paired key'
        groups = collections.defaultdict(list)
        rotations = []
        for key,row in keyed.items():
            if key[-1] != 'candidate': continue
            control = keyed[key[:-1]+('control',)]
            assert row['winner'] is not None and control['winner'] is not None, 'incomplete paired arm'
            assert row['mapVersion']==control['mapVersion'] and row['rulesVersion']==control['rulesVersion'] and row['engineRulesVersion']==control['engineRulesVersion']
            assert comparison is not None, 'missing frozen two-artifact provenance'
            assert row['buildID']==comparison['candidateSource'] and control['buildID']==comparison['anchorSource'], 'arm source mismatch'
            assert row['policies']==['naval-expert-v1' if seat==row['focalChair'] else 'naval-traditional-v1' for seat in range(players)]
            assert control['policies']==['naval-traditional-v1']*players
            groups[key[:4]].append((int(row['winner']==row['focalChair']),int(control['winner']==control['focalChair'])))
            rotations.append((int(row['winner']==row['focalChair']),int(control['winner']==control['focalChair'])))
        assert all(len(g)==players for g in groups.values()), 'missing chair rotation'
        assert all(sum(c for _,c in g)==1 for g in groups.values()), 'control not exactly table null'
        clusters = collections.defaultdict(list)
        for key,values in sorted(groups.items()):
            clusters[key[:3]].append(sum(c-t for c,t in values)/players)
        assert len(clusters)==12
        expected = 11 if players==3 else 7
        assert all(len(values)==expected for values in clusters.values())
        rng = random.Random(20261004)
        boot = sorted(sum(sum(rng.choice(values) for _ in values) for values in clusters.values())/(12*expected) for _ in range(20000))
        delta = sum(sum(values) for values in clusters.values())/(12*expected)
        ci = [boot[499],boot[19499]]
        candidate_mean = statistics.mean(c for c,t in rotations)
        control_mean = statistics.mean(t for c,t in rotations)
        covariance = statistics.mean(c*t for c,t in rotations)-candidate_mean*control_mean
        variance_product = candidate_mean*(1-candidate_mean)*control_mean*(1-control_mean)
        rotation_correlation = covariance/math.sqrt(variance_product) if variance_product>0 else None
        entry['paired'] = dict(rotationCorrelation=rotation_correlation, clusterControlVariance=0, correlationUsedForSampleDiscount=False, seedClusters=len(groups), rotations=len(rotations), difference=delta, difference95CI=ci, bootstrapSamples=20000, bootstrapSeed=20261004, substantiveGatePassed=delta>=.10 and ci[0]>0)
    report['byTable'][players] = entry

latencies = []
for file in root.glob('*.timing'):
    for line in file.read_text().splitlines():
        match = re.search(r'decisions=(\d+) p95=([\d.]+)ms p99=([\d.]+)ms over50=(\d+) over150=(\d+)',line)
        if match: latencies.append(tuple(map(float,match.groups())))
if latencies:
    decisions = int(sum(r[0] for r in latencies))
    over50 = int(sum(r[3] for r in latencies)); over150=int(sum(r[4] for r in latencies))
    report['hostLatency'] = dict(decisions=decisions, over50=over50, over150=over150, fractionOver50=over50/decisions,fractionOver150=over150/decisions,p95GatePassed=over50/decisions<=.05,p99GatePassed=over150/decisions<=.01, gameP95Max=max(r[1] for r in latencies), gameP99Max=max(r[2] for r in latencies))
(root/'analysis.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(json.dumps({key:value for key,value in report.items() if key!='byTable'},indent=2))
for players,entry in report['byTable'].items():
    print(players,json.dumps({'overall':entry['overall'],'arms':entry['arms'],'paired':entry.get('paired')},sort_keys=True))
