#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <new>
#include <stdexcept>
#include <tuple>
#include <type_traits>
#include <utility>
#include <vector>

#ifdef RMMO_REAL_GODOT_CORE
#include "core/templates/local_vector.h"
#include "core/templates/tuple.h"
#include "core/templates/vector.h"
#else
#define _FORCE_INLINE_ inline
#endif
inline thread_local int test_queue_lock_depth = 0;
inline thread_local uint64_t test_queue_lock_calls = 0;

struct BinaryMutex {
	std::mutex native;
	void lock() { native.lock(); ++test_queue_lock_depth; ++test_queue_lock_calls; }
	void unlock() { --test_queue_lock_depth; native.unlock(); }
};
template <typename M> class MutexLock {
	M &mutex;
	bool held = true;
public:
	explicit MutexLock(M &p_mutex) : mutex(p_mutex) { mutex.lock(); }
	~MutexLock() { if (held) { mutex.unlock(); } }
	void temp_unlock() { held = false; mutex.unlock(); }
	void temp_relock() { mutex.lock(); held = true; }
	void lock() { temp_relock(); }
	void unlock() { temp_unlock(); }
};
template <typename M> MutexLock(M &) -> MutexLock<M>;
struct ConditionVariable {
	std::condition_variable_any native;
	void notify_one() { native.notify_one(); }
	template <typename M> void wait(MutexLock<M> &lock) { native.wait(lock); }
};
#ifndef RMMO_REAL_GODOT_CORE
template <typename T> class LocalVector {
	std::vector<T> data;
public:
	void reserve(size_t size) { data.reserve(size); }
	void resize(size_t size) { data.resize(size); }
	size_t size() const { return data.size(); }
	void clear() { data.clear(); }
	T &operator[](size_t index) { return data[index]; }
};
template <typename... T> using Tuple = std::tuple<T...>;
template <size_t... I> using IndexSequence = std::index_sequence<I...>;
template <size_t N> using BuildIndexSequence = std::make_index_sequence<N>;
template <size_t I, typename... T> auto &tuple_get(std::tuple<T...> &value) { return std::get<I>(value); }
#endif
