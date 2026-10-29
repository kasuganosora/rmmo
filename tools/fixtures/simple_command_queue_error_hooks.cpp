// Standalone hooks only. Allocation and container implementations are actual
// Godot sources; the engine logging subsystem is not bootstrapped by this test.
#include "core/error/error_macros.h"
#include <cstdio>
#include <cstdlib>

void _err_print_error(const char *, const char *, int, const char *error, bool, ErrorHandlerType) {
	std::fprintf(stderr, "%s\n", error); std::abort();
}
void _err_print_error(const char *, const char *, int, const char *error, const char *, bool, ErrorHandlerType) {
	std::fprintf(stderr, "%s\n", error); std::abort();
}
void _err_print_index_error(const char *, const char *, int, int64_t, int64_t, const char *, const char *, const char *, bool, bool) {
	std::abort();
}
void _err_flush_stdout() { std::fflush(stdout); }
