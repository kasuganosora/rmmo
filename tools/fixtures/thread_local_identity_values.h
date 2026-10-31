#pragma once

#include <atomic>
#include <cstdint>

// Match Godot's dynamic TLS initializer in a separate translation unit.
// Keep the getter inline, as Thread::get_caller_id() is in the engine.
struct ThreadIdentityFixture {
	static std::atomic<std::uint64_t> counter;
	static thread_local std::uint64_t caller_id;
	static inline std::uint64_t get() { return caller_id; }
	static inline void set(std::uint64_t id) { caller_id = id; }
};
