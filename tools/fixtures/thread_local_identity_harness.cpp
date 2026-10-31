// Standalone Windows reproduction of the TLS getter seen in Godot GDB stacks.
// Build both translation units without LTO, with each candidate toolchain.
#include "thread_local_identity_values.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <chrono>
#include <cstdlib>
#include <iostream>
#include <set>
#include <thread>
#include <vector>

using Clock = std::chrono::steady_clock;

static void require(bool value) {
	if (!value) {
		std::cerr << "identity contract failed\n";
		std::exit(1);
	}
}

static std::uint64_t thread_cpu_100ns() {
	FILETIME created{}, exited{}, kernel{}, user{};
	require(GetThreadTimes(GetCurrentThread(), &created, &exited, &kernel, &user));
	auto value = [](FILETIME t) { return (std::uint64_t(t.dwHighDateTime) << 32) | t.dwLowDateTime; };
	return value(kernel) + value(user);
}

int main(int argc, char **argv) {
	const std::uint64_t iterations = argc > 1 ? std::strtoull(argv[1], nullptr, 10) : 1000000;
	require(iterations > 0 && iterations <= 100000000);
	ThreadIdentityFixture::set(1);
	std::set<std::uint64_t> all_ids;
	for (int count : {1, 4, 12}) {
		std::atomic<int> ready{0};
		std::atomic<bool> start{false};
		std::vector<std::thread> threads;
		std::vector<std::uint64_t> ids(count), sums(count), cpus(count);
		std::vector<double> wall_ms(count);
		for (int index = 0; index < count; ++index) {
			threads.emplace_back([&, index] {
				const auto id = ThreadIdentityFixture::get();
				ids[index] = id;
				require(id > 1);
				// Verify full-width values and per-thread updates before timing.
				ThreadIdentityFixture::set(0x8000000100000000ULL + index);
				require(ThreadIdentityFixture::get() == 0x8000000100000000ULL + index);
				ThreadIdentityFixture::set(id);
				ready.fetch_add(1, std::memory_order_release);
				while (!start.load(std::memory_order_acquire)) {
					std::this_thread::yield();
				}
				auto cpu_start = thread_cpu_100ns();
				auto began = Clock::now();
				std::uint64_t sum = 0;
				for (std::uint64_t n = 0; n < iterations; ++n) {
					sum += ThreadIdentityFixture::get();
				}
				wall_ms[index] = std::chrono::duration<double, std::milli>(Clock::now() - began).count();
				cpus[index] = thread_cpu_100ns() - cpu_start;
				sums[index] = sum;
				require(ThreadIdentityFixture::get() == id);
			});
		}
		while (ready.load(std::memory_order_acquire) != count) {
			std::this_thread::yield();
		}
		auto began = Clock::now();
		start.store(true, std::memory_order_release);
		for (auto &thread : threads) {
			thread.join();
		}
		auto elapsed = std::chrono::duration<double, std::milli>(Clock::now() - began).count();
		std::uint64_t sum = 0, cpu = 0;
		for (int index = 0; index < count; ++index) {
			require(all_ids.insert(ids[index]).second);
			require(sums[index] == ids[index] * iterations);
			sum += sums[index];
			cpu += cpus[index];
		}
		require(ThreadIdentityFixture::get() == 1);
		std::cout << "{\"threads\":" << count << ",\"calls_per_thread\":" << iterations
				  << ",\"wall_ms\":" << elapsed << ",\"thread_cpu_ms\":" << double(cpu) / 10000.0
				  << ",\"checksum\":" << sum << ",\"identity_passed\":true,\"worker_wall_ms\":[";
		for (int index = 0; index < count; ++index) {
			std::cout << (index ? "," : "") << wall_ms[index];
		}
		std::cout << "]}\n";
	}
	return 0;
}
