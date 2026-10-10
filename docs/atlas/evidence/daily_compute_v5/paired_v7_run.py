import subprocess, ctypes, os, json, time, hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[1]
results=[]
for repeat in range(3):
    order=[('before',root/'.dbg/daily-v6-project'),('after',root)]
    if repeat%2: order.reverse()
    for label,project in order:
        tag=f'v7-{label}-{repeat}'
        env=dict(os.environ,FROZEN_TAG=tag)
        hashes={p:hashlib.sha256((project/p).read_bytes()).hexdigest() for p in ['scripts/simulation/simulation.gd','scripts/core/pathfinding.gd','scripts/ai/ai_world_view.gd','scripts/state/game_state.gd','scripts/simulation/rules/supply_rules.gd']}
        started=time.time()
        with (root/f'.dbg/{tag}.stdout.txt').open('w',encoding='utf-8') as out:
            p=subprocess.Popen(['D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe','--headless','--path',str(project),'--script','res://.dbg/frozen_v3_probe.gd'],env=env,stdout=out,stderr=subprocess.STDOUT)
            assert ctypes.windll.kernel32.SetProcessAffinityMask(ctypes.c_void_p(p._handle),ctypes.c_size_t(16))
            print(tag,p.pid,flush=True)
            code=p.wait()
        profile=project/f'.dbg/frozen-profile-{tag}.jsonl'
        rows=[json.loads(l) for l in profile.read_text(encoding='utf-8').splitlines()] if profile.exists() else []
        assert len(rows)==30,'Incomplete benchmark'
        if label=='after':
            oracle=[json.loads(l) for l in (root/'.dbg/frozen-profile-v6-after-0.jsonl').read_text(encoding='utf-8').splitlines()]
            assert [r['sha256'] for r in rows]==[r['sha256'] for r in oracle],'Packed movement cache changes simulation'
        results.append({'label':label,'repeat':repeat,'tag':tag,'project':str(project),'pid':p.pid,'affinity_mask':16,'started_unix':started,'exit_code':code,'source_hashes':hashes,'movement_matches_pre_packed_cache':label=='after'})
        (root/'.dbg/v7-run-metadata.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
        print(tag,'exit',code,flush=True)
        if code: raise SystemExit(code)
