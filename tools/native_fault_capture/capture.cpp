// Opt-in Windows x64 diagnostic extension. Not registered by the game/editor.
// Normal execution only installs a VEH and records the initial module map.
// A first access violation records context/unwind addresses, then lets the
// original exception machinery continue. It does not swallow or repair faults.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <psapi.h>
#include <cstdio>
#include <cstdint>
#include "gdextension_interface.gen.h"

static HANDLE output = INVALID_HANDLE_VALUE;
static PVOID handler = nullptr;
static volatile LONG captured = 0;
static DWORD main_tid = 0;
static GDExtensionInterfaceGetProcAddress api = nullptr;
static GDExtensionClassLibraryPtr library = nullptr;

static void write_line(const char *line, int size) {
	if (output == INVALID_HANDLE_VALUE || size <= 0) return;
	DWORD written = 0;
	WriteFile(output, line, static_cast<DWORD>(size), &written, nullptr);
}

static LONG CALLBACK capture_exception(EXCEPTION_POINTERS *exception) {
	const auto *record = exception->ExceptionRecord;
	if (record->ExceptionCode != EXCEPTION_ACCESS_VIOLATION && record->ExceptionCode != EXCEPTION_ILLEGAL_INSTRUCTION) return EXCEPTION_CONTINUE_SEARCH;
	if (InterlockedCompareExchange(&captured, 1, 0) != 0) return EXCEPTION_CONTINUE_SEARCH;
	// No Godot, renderer, symbol server, heap allocation, or other-thread pause.
	char line[1024];
	CONTEXT context = *exception->ContextRecord;
	int n = std::snprintf(line, sizeof(line), "fault\t%08lx\ttid=%lu\tmain=%lu\tpc=%016llx\tsp=%016llx\taccess=%llu\taddress=%016llx\n",
		record->ExceptionCode, GetCurrentThreadId(), main_tid, context.Rip, context.Rsp,
		record->NumberParameters > 0 ? static_cast<unsigned long long>(record->ExceptionInformation[0]) : 0,
		record->NumberParameters > 1 ? static_cast<unsigned long long>(record->ExceptionInformation[1]) : 0);
	write_line(line, n);
	// Preserve the actual exception context even if a corrupted stack prevents
	// virtual unwinding. The executable's DWARF symbols are decoded offline.
	n = std::snprintf(line, sizeof(line), "registers\trax=%016llx\trbx=%016llx\trcx=%016llx\trdx=%016llx\trsi=%016llx\trdi=%016llx\trbp=%016llx\tr8=%016llx\tr9=%016llx\tr10=%016llx\tr11=%016llx\tr12=%016llx\tr13=%016llx\tr14=%016llx\tr15=%016llx\n",
		context.Rax, context.Rbx, context.Rcx, context.Rdx, context.Rsi, context.Rdi, context.Rbp,
		context.R8, context.R9, context.R10, context.R11, context.R12, context.R13, context.R14, context.R15);
	write_line(line, n);
	DWORD64 stack[64] = {};
	SIZE_T read = 0;
	if (ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<void *>(context.Rsp), stack, sizeof(stack), &read)) {
		for (unsigned int i = 0; i < read / sizeof(DWORD64); ++i) {
			n = std::snprintf(line, sizeof(line), "stack\t%u\t%016llx\n", i, stack[i]);
			write_line(line, n);
		}
	}
	FlushFileBuffers(output); // Raw context survives a failing unwind as well.
	for (unsigned int i = 0; i < 64; ++i) {
		n = std::snprintf(line, sizeof(line), "frame\t%u\t%016llx\t%016llx\n", i, context.Rip, context.Rsp);
		write_line(line, n);
		DWORD64 base = 0;
		PRUNTIME_FUNCTION entry = RtlLookupFunctionEntry(context.Rip, &base, nullptr);
		const DWORD64 old_sp = context.Rsp;
		if (entry) {
			PVOID data = nullptr;
			DWORD64 establisher = 0;
			RtlVirtualUnwind(UNW_FLAG_NHANDLER, base, context.Rip, entry, &context, &data, &establisher, nullptr);
		} else {
			// Leaf frames and execute-at-null have no function-table entry.
			DWORD64 return_address = 0;
			if (!ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<void *>(context.Rsp), &return_address, sizeof(return_address), &read) || read != sizeof(return_address)) break;
			context.Rip = return_address;
			context.Rsp += sizeof(return_address);
		}
		if (context.Rip == 0 || context.Rsp <= old_sp || context.Rsp - old_sp > 16 * 1024 * 1024) break;
	}
	FlushFileBuffers(output);
	return EXCEPTION_CONTINUE_SEARCH;
}

static bool arm_capture() {
	wchar_t path[32768];
	DWORD count = GetEnvironmentVariableW(L"RMMO_FAULT_CAPTURE_FILE", path, 32768);
	if (!count || count >= 32768) return false;
	output = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
	if (output == INVALID_HANDLE_VALUE) return false;
	main_tid = GetCurrentThreadId();
	char line[4096];
	int n = std::snprintf(line, sizeof(line), "capture-v1\tpid=%lu\tmain=%lu\n", GetCurrentProcessId(), main_tid);
	write_line(line, n);
	HMODULE modules[512];
	DWORD bytes = 0;
	if (EnumProcessModules(GetCurrentProcess(), modules, sizeof(modules), &bytes)) {
		const DWORD count_modules = bytes / sizeof(HMODULE) < 512 ? static_cast<DWORD>(bytes / sizeof(HMODULE)) : 512;
		for (DWORD i = 0; i < count_modules; ++i) {
			MODULEINFO info = {};
			wchar_t name[1024];
			char utf8[3072];
			if (!GetModuleInformation(GetCurrentProcess(), modules[i], &info, sizeof(info))) continue;
			if (!GetModuleFileNameW(modules[i], name, 1024)) continue;
			if (!WideCharToMultiByte(CP_UTF8, 0, name, -1, utf8, sizeof(utf8), nullptr, nullptr)) continue;
			n = std::snprintf(line, sizeof(line), "module\t%016llx\t%08lx\t%s\n", reinterpret_cast<unsigned long long>(info.lpBaseOfDll), info.SizeOfImage, utf8);
			write_line(line, n);
		}
	}
	wchar_t disabled[8];
	bool off = GetEnvironmentVariableW(L"RMMO_FAULT_CAPTURE_DISABLED", disabled, 8) && disabled[0] == L'1';
	if (!off) handler = AddVectoredExceptionHandler(1, capture_exception);
	n = std::snprintf(line, sizeof(line), "armed\t%d\n", handler != nullptr);
	write_line(line, n); FlushFileBuffers(output);
	return off || handler != nullptr;
}

// These controlled faults are available only to a dedicated fixture process.
// A game diagnostic cannot invoke them unless this second opt-in is also set.
static volatile uintptr_t fault_address = 0;
extern "C" __declspec(dllexport) __attribute__((noinline)) void rmmo_test_read_null() {
	volatile unsigned char value = *reinterpret_cast<volatile unsigned char *>(fault_address);
	(void)value;
}
extern "C" __declspec(dllexport) __attribute__((noinline)) void rmmo_test_execute_null() {
	reinterpret_cast<void (*)()>(fault_address)();
	asm volatile("" ::: "memory"); // Keep the real return address for the fixture.
}
static void call_fault(void *kind) {
	if (reinterpret_cast<intptr_t>(kind) == 1) rmmo_test_read_null();
	else rmmo_test_execute_null();
}
static void method_call(void *kind, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *, GDExtensionInt argc, GDExtensionVariantPtr, GDExtensionCallError *error) {
	error->error = argc ? GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS : GDEXTENSION_CALL_OK;
	if (!argc) call_fault(kind);
}
static void method_ptrcall(void *kind, GDExtensionClassInstancePtr, const GDExtensionConstTypePtr *, GDExtensionTypePtr) { call_fault(kind); }
static void free_instance(void *, GDExtensionClassInstancePtr) {}
static bool fixture_class = false;

static void initialize(void *, GDExtensionInitializationLevel level) {
	if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
	wchar_t test[8];
	if (!GetEnvironmentVariableW(L"RMMO_FAULT_CAPTURE_TEST", test, 8) || test[0] != L'1') return;
	auto name_new = reinterpret_cast<GDExtensionInterfaceStringNameNewWithUtf8Chars>(api("string_name_new_with_utf8_chars"));
	auto destroy = reinterpret_cast<GDExtensionInterfaceVariantGetPtrDestructor>(api("variant_get_ptr_destructor"))(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
	void *name = nullptr, *parent = nullptr;
	name_new(&name, "NativeFaultProbe"); name_new(&parent, "RefCounted");
	GDExtensionClassCreationInfo6 info = {};
	info.is_abstract = true; info.is_exposed = true; info.free_instance_func = free_instance;
	reinterpret_cast<GDExtensionInterfaceClassdbRegisterExtensionClass6>(api("classdb_register_extension_class6"))(library, &name, &parent, &info);
	for (intptr_t kind = 1; kind <= 2; ++kind) {
		void *method_name = nullptr;
		name_new(&method_name, kind == 1 ? "read_null" : "execute_null");
		GDExtensionClassMethodInfo method = {};
		method.name = &method_name; method.method_userdata = reinterpret_cast<void *>(kind);
		method.call_func = method_call; method.ptrcall_func = method_ptrcall;
		method.method_flags = GDEXTENSION_METHOD_FLAGS_DEFAULT | GDEXTENSION_METHOD_FLAG_STATIC;
		reinterpret_cast<GDExtensionInterfaceClassdbRegisterExtensionClassMethod>(api("classdb_register_extension_class_method"))(library, &name, &method);
		destroy(&method_name);
	}
	fixture_class = true;
	destroy(&parent); destroy(&name);
}
static void deinitialize(void *, GDExtensionInitializationLevel level) {
	if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
	if (fixture_class) {
		void *name = nullptr;
		reinterpret_cast<GDExtensionInterfaceStringNameNewWithUtf8Chars>(api("string_name_new_with_utf8_chars"))(&name, "NativeFaultProbe");
		reinterpret_cast<GDExtensionInterfaceClassdbUnregisterExtensionClass>(api("classdb_unregister_extension_class"))(library, &name);
		reinterpret_cast<GDExtensionInterfaceVariantGetPtrDestructor>(api("variant_get_ptr_destructor"))(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&name);
	}
	if (handler) { RemoveVectoredExceptionHandler(handler); handler = nullptr; }
	if (output != INVALID_HANDLE_VALUE) { CloseHandle(output); output = INVALID_HANDLE_VALUE; }
}
extern "C" __declspec(dllexport) GDExtensionBool rmmo_capture_init(GDExtensionInterfaceGetProcAddress get_proc, GDExtensionClassLibraryPtr class_library, GDExtensionInitialization *init) {
	api = get_proc; library = class_library;
	if (!arm_capture()) return false;
	init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	init->initialize = initialize; init->deinitialize = deinitialize; init->userdata = nullptr;
	return true;
}
