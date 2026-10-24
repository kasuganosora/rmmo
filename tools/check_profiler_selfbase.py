"""Run the isolated self-base profiler regression. Default is a dry plan.
Only --run launches two sequential HEADLESS owned target/receiver pairs.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import shutil
import subprocess
import time

PROJECT = Path(__file__).resolve().parents[1]
FIXTURE_SOURCE = PROJECT / "tools/profiler_selfbase_fixture"
OUT = FIXTURE = RECEIVER = None
DECODER = PROJECT / "tools/summarize_godot_profiler.gd"


def sha(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def child(command, **kwargs):
    return subprocess.Popen(command, creationflags=subprocess.CREATE_NO_WINDOW, **kwargs)


def stop_owned(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=10)


def write_json(path, value):
    with path.open("x", encoding="utf-8") as file:
        json.dump(value, file, indent=2, ensure_ascii=False)


def analyze(summary, fixture, native):
    rows = summary.get("function_totals", [])
    def exact(file, function):
        matches = [row for row in rows if row["signature"].startswith("res://"+file+"::")
                   and row["signature"].endswith("::"+function)]
        return matches[0] if len(matches) == 1 else None
    def native_row(file, function, method):
        matches = [row for row in rows if row["signature"].startswith("res://"+file+"::")
                   and ("::"+function+" [native ") in row["signature"]
                   and row["signature"].endswith("."+method+"]")]
        return matches[0] if len(matches) == 1 else None
    checks, evidence = [], {}
    def check(name, passed, detail=None):
        checks.append({"name":name, "passed":bool(passed), "detail":detail})
    check("fixture_semantics", fixture is not None and not fixture.get("failures", ["missing"]))
    check("engine_errors", not summary.get("engine_errors"))
    samples = fixture.get("rows", []) if fixture else []
    phases = ("direct_script", "two_super_levels", "direct_native_signal",
              "super_native_signal", "builtin_signal")
    check("five_phases_eight_calls", all(sum(row.get("phase")==phase for row in samples)==8 for phase in phases))
    expected = (("base.gd","inherited_work",18), ("child.gd","inherited_work",9),
                ("leaf.gd","inherited_work",9), ("base.gd","_on_native_work",24),
                ("child.gd","native_direct_emit",8), ("child.gd","native_selfbase_emit",8),
                ("child.gd","builtin_signal_emit",8), ("child.gd","native_selfbase_id",1))
    for file, function, count in expected:
        row = exact(file, function)
        check("calls:"+file+":"+function, row is not None and row["calls"]==count,
              None if row is None else row["calls"])
        if row is not None:
            evidence[file+":"+function] = row
    valid = all(check["passed"] for check in checks)
    accounting = []
    for file in ("child.gd", "leaf.gd"):
        row = exact(file, "inherited_work")
        ratio = row["self_ms"]/row["total_ms"] if row and row["total_ms"]>0 else None
        accounting.append({"name":"script_super_self:"+file,
                           "passed":ratio is not None and ratio<.20,
                           "duplicate_detected":ratio is not None and ratio>.50,
                           "self_over_total":ratio,
                           "note":"Own body is a single super dispatch and +1; exact call counts and returns checked separately."})
    native_super = exact("child.gd","native_selfbase_emit")
    native_direct = exact("child.gd","native_direct_emit")
    for function in ("native_direct_emit","native_selfbase_emit"):
        row = exact("child.gd",function)
        nr = native_row("child.gd",function,"emit_signal")
        ratio = row["self_ms"]/row["total_ms"] if row and row["total_ms"]>0 else None
        if nr is not None:evidence["native:"+function]=nr
        accounting.append({"name":"native_emit_contract:"+function,
                           "passed":((nr is not None and nr["calls"]==8 and ratio is not None and ratio<.20)
                                     if native else (nr is None and ratio is not None and ratio>.50)),
                           "self_over_total":ratio,"native_calls":None if nr is None else nr["calls"],
                           "note":"With native profiling off, direct MethodBind keeps callback time in script self."})
    nr = native_row("child.gd","native_selfbase_id","get_instance_id")
    accounting.append({"name":"native_super_id_row",
                       "passed":(nr is not None and nr["calls"]==1) if native else nr is None,
                       "native_calls":None if nr is None else nr["calls"]})
    signal = exact("child.gd","builtin_signal_emit")
    return {"fixture_valid":valid, "semantic_and_count_checks":checks,
            "accounting_checks":accounting, "accounting_pass":valid and all(r["passed"] for r in accounting),
            "script_super_duplicate":valid and all(r["duplicate_detected"] for r in accounting[:2]),
            "evidence":evidence, "builtin_signal_boundary":signal,
            "note":"No sum of inclusive totals or worker rows is treated as frame wall time. Typed Signal.emit attribution is informational."}


def run_mode(args, native, engine_sha):
    name = args.name + ("_native_on" if native else "_native_off")
    prefix = OUT/name
    with socket.socket() as probe:
        probe.bind(("127.0.0.1",0))
        port = probe.getsockname()[1]
    live = Path(str(prefix)+".live.log")
    binary = Path(str(prefix)+".bin")
    summary_path = Path(str(prefix)+".summary.json")
    receiver_command = [str(args.engine),"--headless","--path",str(FIXTURE),"--script",str(RECEIVER),"--",
                        "--output="+str(binary),"--port="+str(port),"--phase-log="+str(live),
                        "--wait-marker=SELFBASE_FIXTURE_BEGIN","--timeout-seconds=90","--max-functions=256"]
    if not native:receiver_command.append("--without-native-profile")
    target_command = [str(args.engine),"--headless","--disable-crash-handler","--path",str(FIXTURE),
                      "--debug","--remote-debug","tcp://127.0.0.1:"+str(port),
                      "--script","res://main.gd","--log-file",str(live)]
    decoder_command = [str(args.engine),"--headless","--path",str(FIXTURE),"--script",str(DECODER),"--",
                       "--input="+str(binary),"--output="+str(summary_path)]
    if native:decoder_command.append("--native-callers")
    env = os.environ.copy()
    env["RMMO_PROFILE_NATIVE_CALLERS"]="1"
    manifest = {"name":name,"engine":str(args.engine),"engine_sha256":engine_sha,"native":native,
                "receiver":receiver_command,"target":target_command,"decoder":decoder_command,
                "fixture_sources":{p.name:sha(p) for p in FIXTURE.iterdir() if p.suffix in (".gd",".godot")},
                "receiver_sha256":sha(RECEIVER),"decoder_sha256":sha(DECODER)}
    receiver = target = None
    receiver_log = Path(str(prefix)+".receiver.log")
    try:
        with receiver_log.open("xb") as receiver_output, Path(str(prefix)+".target.log").open("xb") as target_output:
            receiver=child(receiver_command,env=env,stdout=receiver_output,stderr=subprocess.STDOUT)
            manifest["receiver_pid"]=receiver.pid
            deadline=time.monotonic()+12
            while time.monotonic()<deadline and receiver.poll() is None:
                if "OFFICIAL_PROFILER_LISTENING" in receiver_log.read_text(encoding="utf-8",errors="replace"):
                    break
                time.sleep(.05)
            else:
                raise RuntimeError("Receiver failed to acquire its unique loopback port")
            target=child(target_command,env=env,stdout=target_output,stderr=subprocess.STDOUT)
            manifest["target_pid"]=target.pid
            write_json(Path(str(prefix)+".launch.json"),manifest)
            target_exit=target.wait(timeout=60)
            receiver_exit=receiver.wait(timeout=15)
        with Path(str(prefix)+".decoder.log").open("xb") as decoder_output:
            decoded=subprocess.run(decoder_command,env=env,stdout=decoder_output,stderr=subprocess.STDOUT,
                                   timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
        fixture=None
        for line in live.read_text(encoding="utf-8",errors="replace").splitlines():
            if line.startswith("SELFBASE_FIXTURE_RESULT "):
                fixture=json.loads(line.removeprefix("SELFBASE_FIXTURE_RESULT "))
        summary=json.loads(summary_path.read_text(encoding="utf-8")) if summary_path.exists() else {}
        report={"manifest":manifest,"target_exit":target_exit,"receiver_exit":receiver_exit,
                "decoder_exit":decoded.returncode,"fixture":fixture,"summary_path":str(summary_path)}
        report.update(analyze(summary,fixture,native))
        report["fixture_valid"] &= target_exit==receiver_exit==decoded.returncode==0
        report["accounting_pass"] &= report["fixture_valid"]
        report["script_super_duplicate"] &= report["fixture_valid"]
        write_json(Path(str(prefix)+".result.json"),report)
        return report
    finally:
        stop_owned(target)
        stop_owned(receiver)


def main():
    global OUT, FIXTURE, RECEIVER
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run",action="store_true")
    parser.add_argument("--engine",type=Path,required=True)
    parser.add_argument("--output-dir",type=Path,required=True)
    parser.add_argument("--name",default="selfbase166_"+time.strftime("%Y%m%d_%H%M%S"))
    parser.add_argument("--expect",choices=("baseline","patched","observe"),default="observe")
    args=parser.parse_args()
    if "/" in args.name or "\\" in args.name or ":" in args.name:parser.error("Name must be one filename component")
    if not args.name or args.name in (".", ".."):parser.error("Name must be one filename component")
    OUT=args.output_dir.resolve()
    if OUT.is_relative_to(PROJECT):parser.error("--output-dir must be outside the Godot project")
    FIXTURE=OUT/(args.name+".fixture")
    RECEIVER=FIXTURE/"receiver.gd"
    for path in (args.engine,FIXTURE_SOURCE/"receiver.gd",DECODER,FIXTURE_SOURCE/"main.gd"):
        if not path.is_file():parser.error("Missing "+str(path))
    if not args.run:
        print(json.dumps({"run":False,"engine":str(args.engine),"fixture":str(FIXTURE),
                          "native_modes":[False,True],"expect":args.expect,
                          "note":"No engine, receiver, decoder, copy, or hash work launched."},indent=2))
        return
    OUT.mkdir(parents=True,exist_ok=True)
    shutil.copytree(FIXTURE_SOURCE,FIXTURE,
                    ignore=shutil.ignore_patterns(".gdignore",".godot","*.uid"))
    engine_sha=sha(args.engine)
    results=[run_mode(args,native,engine_sha) for native in (False,True)]
    valid=all(row["fixture_valid"] for row in results)
    reproduced=valid and all(row["script_super_duplicate"] for row in results)
    fixed=valid and all(row["accounting_pass"] for row in results)
    expected=valid if args.expect=="observe" else reproduced if args.expect=="baseline" else fixed
    final={"name":args.name,"engine_sha256":engine_sha,"expect":args.expect,
           "fixture_valid":valid,"baseline_red_reproduced":reproduced,"patched_green":fixed,
           "expected_result":expected,"results":[{k:r[k] for k in ("target_exit","receiver_exit","decoder_exit",
                "fixture_valid","accounting_pass","script_super_duplicate")} for r in results]}
    write_json(OUT/(args.name+".validation.json"),final)
    print(json.dumps(final,indent=2))
    raise SystemExit(0 if expected else 1)


if __name__=="__main__":
    main()

