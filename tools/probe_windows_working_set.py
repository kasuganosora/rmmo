"""Read-only, bounded resident-page classification for a 64-bit Windows PID.

QueryWorkingSet enumerates the current working set; VirtualQueryEx classifies
its regions. No ReadProcessMemory, VirtualLock, trim, target allocation, thread
suspension, privilege escalation or target configuration changes are used.
Run after performance measurements, never inside the measured frame window.

Microsoft API definitions (accessed 2026-10-11):
https://learn.microsoft.com/en-us/windows/win32/api/psapi/nf-psapi-queryworkingset
https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-psapi_working_set_block
https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualqueryex
https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-memory_basic_information
https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-process_memory_counters_ex
"""
import argparse
import bisect
import ctypes as C
import json
import os
import stat
import sys
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

OUTPUT_ROOT = Path("D:/code/rmmo_runtime/review_artifacts")
MAX_BUFFER_BYTES = 256 * 1024 * 1024
MAX_ATTEMPTS = 8
MAX_SECONDS = 25.0
ERROR_BAD_LENGTH = 24
MEM_COMMIT = 0x1000
MEM_TYPES = {0x20000: "MEM_PRIVATE", 0x40000: "MEM_MAPPED", 0x1000000: "MEM_IMAGE"}
PROCESS_ACCESS = 0x0400 | 0x0010  # QUERY_INFORMATION | VM_READ, no mutation rights
U32, U64, WORD, SIZE_T = C.c_uint32, C.c_uint64, C.c_uint16, C.c_size_t


class SystemInfo(C.Structure):
    _fields_ = [("dwOemId", U32), ("dwPageSize", U32),
                ("lpMinimumApplicationAddress", C.c_void_p), ("lpMaximumApplicationAddress", C.c_void_p),
                ("dwActiveProcessorMask", SIZE_T), ("dwNumberOfProcessors", U32),
                ("dwProcessorType", U32), ("dwAllocationGranularity", U32),
                ("wProcessorLevel", WORD), ("wProcessorRevision", WORD)]


class MemoryBasicInformation(C.Structure):
    _fields_ = [("BaseAddress", C.c_void_p), ("AllocationBase", C.c_void_p),
                ("AllocationProtect", U32), ("PartitionId", WORD), ("RegionSize", SIZE_T),
                ("State", U32), ("Protect", U32), ("Type", U32)]


class ProcessMemoryCountersEx(C.Structure):
    _fields_ = [("cb", U32), ("PageFaultCount", U32)] + [(name, SIZE_T) for name in (
        "PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage", "QuotaPagedPoolUsage",
        "QuotaPeakNonPagedPoolUsage", "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage", "PrivateUsage")]


def decode_block(flags):
    # ULONG_PTR bit layout is explicitly documented; avoid compiler-dependent
    # ctypes bitfield packing. The virtual page field begins after 12 bits.
    return flags & 31, (flags >> 5) & 7, bool((flags >> 8) & 1), flags & ~0xFFF


class Api:
    def __init__(self):
        if os.name != "nt" or C.sizeof(C.c_void_p) != 8:
            raise ValueError("Requires 64-bit Python on 64-bit Windows")
        if C.sizeof(MemoryBasicInformation) != 48 or MemoryBasicInformation.RegionSize.offset != 24 \
                or C.sizeof(ProcessMemoryCountersEx) != 80 or C.sizeof(SystemInfo) != 48:
            raise ValueError("Unexpected Windows x64 structure layout")
        self.kernel = C.WinDLL("kernel32.dll", use_last_error=True)
        self.psapi = C.WinDLL("psapi.dll", use_last_error=True)
        declarations = [
            (self.kernel, "OpenProcess", [U32, C.c_int, U32], C.c_void_p),
            (self.kernel, "CloseHandle", [C.c_void_p], C.c_int),
            (self.kernel, "GetSystemInfo", [C.POINTER(SystemInfo)], None),
            (self.kernel, "IsWow64Process", [C.c_void_p, C.POINTER(C.c_int)], C.c_int),
            (self.kernel, "GetExitCodeProcess", [C.c_void_p, C.POINTER(U32)], C.c_int),
            (self.kernel, "VirtualQueryEx", [C.c_void_p, C.c_void_p, C.POINTER(MemoryBasicInformation), SIZE_T], SIZE_T),
            (self.psapi, "QueryWorkingSet", [C.c_void_p, C.c_void_p, U32], C.c_int),
            (self.psapi, "GetProcessMemoryInfo", [C.c_void_p, C.POINTER(ProcessMemoryCountersEx), U32], C.c_int),
        ]
        for dll, name, arguments, result in declarations:
            function = getattr(dll, name)
            function.argtypes, function.restype = arguments, result
            setattr(self, name, function)


def error(report, api, code=None, **detail):
    report["error_count"] += 1
    if len(report["errors"]) < 32:
        value = {"api": api, **detail}
        if code is not None:
            value.update(winerror=code, message=C.FormatError(code).strip())
        report["errors"].append(value)


def memory_info(api, handle, report, phase):
    counters = ProcessMemoryCountersEx()
    counters.cb = C.sizeof(counters)
    C.set_last_error(0)
    if not api.GetProcessMemoryInfo(handle, C.byref(counters), counters.cb):
        error(report, "GetProcessMemoryInfo", C.get_last_error(), phase=phase)
        return None
    result = {name: int(getattr(counters, name)) for name, _ in counters._fields_}
    result["epoch_s"] = time.time()
    result["scope"] = "WorkingSetSize is resident bytes; PrivateUsage is private commit, not private resident bytes or bytes physically stored in the pagefile."
    return result


def exit_code(api, handle, report, phase):
    code = U32()
    C.set_last_error(0)
    if not api.GetExitCodeProcess(handle, C.byref(code)):
        error(report, "GetExitCodeProcess", C.get_last_error(), phase=phase)
        return None
    return int(code.value)


def working_set(api, handle, report, deadline):
    allocation = 64 * 1024
    for attempt in range(MAX_ATTEMPTS):
        if time.monotonic() >= deadline:
            error(report, "QueryWorkingSet", reason="deadline_before_attempt")
            break
        buffer = C.create_string_buffer(allocation)
        C.set_last_error(0)
        started = time.monotonic()
        ok = bool(api.QueryWorkingSet(handle, buffer, allocation))
        code = C.get_last_error() if not ok else 0
        count = int(U64.from_buffer(buffer).value)
        report["query_attempts"].append({"attempt": attempt + 1, "buffer_bytes": allocation,
            "number_of_entries": count, "ok": ok, "winerror": code,
            "elapsed_ms": (time.monotonic() - started) * 1000})
        # Check by division before constructing a ctypes array or calculating
        # any pointer offset. Python integers do not wrap, DWORD cb still can.
        if count > (MAX_BUFFER_BYTES - 8) // 8:
            error(report, "QueryWorkingSet", reason="required_entries_exceed_256MiB_cap", entries=count)
            return None
        if ok:
            if count > (allocation - 8) // 8:
                error(report, "QueryWorkingSet", reason="successful_count_exceeds_allocated_buffer", entries=count)
                return None
            report["working_set_buffer_bytes"] = allocation
            return buffer, count
        if code != ERROR_BAD_LENGTH:
            error(report, "QueryWorkingSet", code)
            return None
        required = 8 + count * 8
        proposed = max(allocation * 2, required + max(8192, required // 8))
        if allocation == MAX_BUFFER_BYTES or required > MAX_BUFFER_BYTES:
            error(report, "QueryWorkingSet", code, reason="buffer_cap_reached")
            return None
        allocation = min(MAX_BUFFER_BYTES, proposed)
        buffer = None  # Do not retain old buffers while allocating a larger one.
    else:
        error(report, "QueryWorkingSet", ERROR_BAD_LENGTH, reason="bounded_retries_exhausted")
    return None


def classify(api, handle, buffer, count, page_size, max_address, report, deadline):
    blocks = (U64 * count).from_buffer(buffer, 8)
    starts, regions = [], []
    by_type, shared_flags, share_counts, protection = Counter(), Counter(), Counter(), Counter()
    cross = Counter()
    visited, unknown, vq_calls, hits, failure_streak = 0, 0, 0, 0, 0
    for flags in blocks:
        if visited % 4096 == 0 and time.monotonic() >= deadline:
            error(report, "classification", reason="25_second_deadline", remaining_pages=count - visited)
            break
        protect, share_count, shared, address = decode_block(flags)
        category = "UNKNOWN"
        region = None
        index = bisect.bisect_right(starts, address) - 1
        if index >= 0 and address < regions[index]["end"]:
            region = regions[index]; hits += 1
        elif address > max_address:
            error(report, "working_set_block", reason="address_outside_user_range", address=hex(address))
        else:
            mbi = MemoryBasicInformation()
            C.set_last_error(0)
            returned = int(api.VirtualQueryEx(handle, C.c_void_p(address), C.byref(mbi), C.sizeof(mbi)))
            code = C.get_last_error() if returned == 0 else None
            vq_calls += 1
            base, size = int(mbi.BaseAddress or 0), int(mbi.RegionSize)
            if returned != C.sizeof(mbi) or size <= 0 or base > address or address >= base + size or base + size > 1 << 64:
                error(report, "VirtualQueryEx", code, address=hex(address), returned_bytes=returned,
                      reason="api_failure_or_invalid_region")
                failure_streak += 1
            else:
                failure_streak = 0
                region = {"base": base, "end": base + size, "allocation_base": int(mbi.AllocationBase or 0),
                    "region_size": size, "state": int(mbi.State), "type_value": int(mbi.Type),
                    "type": MEM_TYPES.get(int(mbi.Type), "UNKNOWN") if mbi.State == MEM_COMMIT else "NONCOMMITTED",
                    "protect": int(mbi.Protect), "allocation_protect": int(mbi.AllocationProtect),
                    "resident_pages": 0, "ws_shared_flag_pages": 0, "ws_private_flag_pages": 0}
                insertion = bisect.bisect_right(starts, base)
                starts.insert(insertion, base); regions.insert(insertion, region)
        if region is not None:
            category = region["type"]
            region["resident_pages"] += 1
            region["ws_shared_flag_pages" if shared else "ws_private_flag_pages"] += 1
        if category not in MEM_TYPES.values():
            unknown += 1
        by_type[category] += 1
        shared_flags["shared_bit_set" if shared else "shared_bit_clear"] += 1
        share_counts[share_count] += 1
        protection[protect] += 1
        cross[(category, "shared_bit_set" if shared else "shared_bit_clear")] += 1
        visited += 1
        if failure_streak >= 32:
            error(report, "classification", reason="consecutive_region_failures", remaining_pages=count - visited)
            break
    def totals(values):
        return {str(key): {"pages": value, "bytes": value * page_size} for key, value in sorted(values.items())}
    def region_output(region):
        return {"base_address": hex(region["base"]), "allocation_base": hex(region["allocation_base"]),
            "region_size_bytes": region["region_size"], "state": hex(region["state"]), "type": region["type"],
            "protect": hex(region["protect"]), "allocation_protect": hex(region["allocation_protect"]),
            "resident_pages": region["resident_pages"], "resident_bytes": region["resident_pages"] * page_size,
            "ws_shared_flag_bytes": region["ws_shared_flag_pages"] * page_size,
            "ws_private_flag_bytes": region["ws_private_flag_pages"] * page_size}
    # Group sampled regions by allocation base without claiming that unvisited
    # regions/nonresident pages of the allocation were enumerated.
    allocations = {}
    for region in regions:
        allocation = allocations.setdefault(region["allocation_base"], {"pages": 0, "shared": 0, "types": set(), "intervals": []})
        allocation["pages"] += region["resident_pages"]
        allocation["shared"] += region["ws_shared_flag_pages"]
        allocation["types"].add(region["type"])
        allocation["intervals"].append((region["base"], region["end"]))
    top_allocations = []
    for base, allocation in sorted(allocations.items(), key=lambda row: row[1]["pages"], reverse=True)[:32]:
        covered, end = 0, -1
        for low, high in sorted(allocation["intervals"]):
            covered += max(0, high - max(low, end)); end = max(end, high)
        top_allocations.append({"allocation_base": hex(base), "types": sorted(allocation["types"]),
            "resident_pages": allocation["pages"], "resident_bytes": allocation["pages"] * page_size,
            "ws_shared_flag_bytes": allocation["shared"] * page_size,
            "ws_private_flag_bytes": (allocation["pages"] - allocation["shared"]) * page_size,
            "queried_region_extent_bytes": covered, "queried_regions": len(allocation["intervals"])})
    report.update(enumerated_pages=count, enumerated_resident_bytes=count * page_size, classified_pages=visited,
        unclassified_remaining_pages=count - visited, unknown_or_noncommitted_pages=unknown,
        by_region_type=totals(by_type), by_ws_shared_flag=totals(shared_flags), by_ws_share_count=totals(share_counts),
        by_ws_protection_code=totals(protection), region_shared_cross=[{"type": kind, "ws_flag": flag, "pages": pages, "bytes": pages * page_size}
            for (kind, flag), pages in sorted(cross.items())],
        virtual_query_calls=vq_calls, region_cache_hits=hits, cached_regions=len(regions),
        top_regions=[region_output(region) for region in sorted(regions, key=lambda row: row["resident_pages"], reverse=True)[:32]],
        top_allocations=top_allocations)
    return visited == count and unknown == 0


def probe(pid):
    started = time.monotonic()
    report = {"version": 1, "pid": pid, "probe_pid": os.getpid(), "ok": False, "complete": False,
        "started_utc": datetime.now(timezone.utc).isoformat(), "start_epoch_s": time.time(),
        "errors": [], "error_count": 0, "query_attempts": [], "access_mask": hex(PROCESS_ACCESS),
        "buffer_cap_bytes": MAX_BUFFER_BYTES, "attempt_limit": MAX_ATTEMPTS, "deadline_seconds": MAX_SECONDS,
        "scope": "Read-only QueryWorkingSet resident-page snapshot plus cached VirtualQueryEx region metadata; target contents are never read or touched.",
        "limitations": ["QueryWorkingSet does not enumerate non-working-set AWE/large pages; this is not a complete physical-memory inventory.",
            "Shared bit means shareable. ShareCount is capped at 7; neither is an engine resource/texture identity.",
            "MEM_MAPPED/IMAGE may include private copy-on-write resident pages; inspect both region type and working-set Shared bit.",
            "Region metadata is sampled after working-set enumeration and cached within this probe; a changing process is not an atomic snapshot.",
            "PrivateUsage is private commit, not RSS. Mapped-page sizes do not identify GPU/driver/texture ownership or VRAM.",
            "Top allocation extents cover only queried regions containing sampled resident pages, not complete allocation/commit totals."]}
    handle, api, classified = None, None, False
    try:
        if type(pid) is not int or not 0 < pid <= 0xFFFFFFFF:
            raise ValueError("PID must be a positive DWORD")
        api = Api()
        C.set_last_error(0)
        handle = api.OpenProcess(PROCESS_ACCESS, False, pid)
        if not handle:
            error(report, "OpenProcess", C.get_last_error())
            return report
        wow64 = C.c_int()
        C.set_last_error(0)
        if not api.IsWow64Process(handle, C.byref(wow64)):
            error(report, "IsWow64Process", C.get_last_error())
            return report
        if wow64.value:
            raise ValueError("This probe intentionally supports native 64-bit target processes only")
        system = SystemInfo(); api.GetSystemInfo(C.byref(system))
        page_size = int(system.dwPageSize)
        # The documented working-set block has a fixed 12-bit flag prefix.
        # Reject a different base page size rather than silently misdecode it.
        if page_size != 4096:
            raise ValueError("Unsupported base page size for x64 working-set block: " + str(page_size))
        report.update(page_size=page_size, pointer_bits=64, architecture=int(system.dwOemId & 0xFFFF))
        report["exit_code_before"] = exit_code(api, handle, report, "before")
        report["memory_before"] = memory_info(api, handle, report, "before")
        if report["exit_code_before"] != 259:
            error(report, "target_lifetime", reason="process_not_active_before_sample")
            return report
        result = working_set(api, handle, report, started + MAX_SECONDS)
        if result is not None:
            buffer, count = result
            report["working_set_snapshot_epoch_s"] = time.time()
            classified = classify(api, handle, buffer, count, page_size,
                int(system.lpMaximumApplicationAddress or 0), report, started + MAX_SECONDS)
    except (OSError, ValueError, MemoryError, OverflowError) as failure:
        error(report, "probe", reason=type(failure).__name__, message=str(failure))
    finally:
        if handle and api:
            report["memory_after"] = memory_info(api, handle, report, "after")
            report["exit_code_after"] = exit_code(api, handle, report, "after")
            if report["exit_code_after"] != 259:
                error(report, "target_lifetime", reason="process_not_active_after_sample")
            C.set_last_error(0)
            if not api.CloseHandle(handle):
                error(report, "CloseHandle", C.get_last_error())
        before, after = report.get("memory_before"), report.get("memory_after")
        if before and after:
            report["memory_delta"] = {field: after[field] - before[field] for field in (
                "WorkingSetSize", "PrivateUsage", "PageFaultCount", "PeakWorkingSetSize")}
            if "enumerated_resident_bytes" in report:
                report["enumerated_minus_rss_before_bytes"] = report["enumerated_resident_bytes"] - before["WorkingSetSize"]
                report["enumerated_minus_rss_after_bytes"] = report["enumerated_resident_bytes"] - after["WorkingSetSize"]
        report["complete"] = bool(classified and before and after and report["error_count"] == 0)
        report["ok"] = report["complete"]
        report.update(end_epoch_s=time.time(), elapsed_ms=(time.monotonic() - started) * 1000)
    return report


def output_path(value):
    path = Path(value)
    if not path.is_absolute():
        raise ValueError("Output path must be absolute")
    path = Path(os.path.abspath(path))
    if not path.is_relative_to(OUTPUT_ROOT) or path.suffix.lower() != ".json":
        raise ValueError("Output must be a JSON beneath D:/code/rmmo_runtime/review_artifacts")
    for parent in (path, *path.parents):
        try:
            info = parent.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            raise ValueError("Symlink/reparse output path rejected")
    if path.exists():
        raise ValueError("Refusing to overwrite an existing report")
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", required=True, type=int)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        target = output_path(args.output)
        report = probe(args.pid)
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("x", encoding="utf-8") as stream:
            json.dump(report, stream, indent=2, ensure_ascii=False); stream.write("\n")
        print(json.dumps({"ok": report["ok"], "complete": report["complete"], "pid": args.pid,
            "output": target.as_posix(), "pages": report.get("enumerated_pages"), "error_count": report["error_count"],
            "elapsed_ms": round(report["elapsed_ms"], 3)}))
        return 0 if report["ok"] else 1
    except (OSError, ValueError) as failure:
        print(json.dumps({"ok": False, "complete": False, "error": str(failure)[:1000]}))
        return 2


if __name__ == "__main__":
    sys.exit(main())
