// Reuse the four safe, permanently-live control-block reproductions.
#define main ownership_fixture_main
#include "simple_command_queue_ownership_harness.cpp"
#undef main
#include <algorithm>
#include <chrono>
#include <thread>

using StableQueue = moved::SimpleCommandQueue; // This file contains extracted production source.

void outcome(const char *variant, const char *name, bool correct, const std::string &details = "") {
	if (!correct) { ++failed; }
	std::cout << "{\"variant\":\"" << variant << "\",\"case\":\"" << name
			  << "\",\"passed\":" << (correct ? "true" : "false") << details << "}\n";
}

struct AddressControl {
	int live = 0, calls = 0, bad_calls = 0, bad_destroys = 0, owning_destroys_locked = 0;
};
struct LocatedOwner {
	AddressControl *control;
	const LocatedOwner *self = this;
	bool owns = true;
	std::array<uint8_t, 96> padding{};
	explicit LocatedOwner(AddressControl &c) : control(&c) { ++control->live; }
	LocatedOwner(LocatedOwner &&p) noexcept : control(p.control), owns(std::exchange(p.owns, false)) {}
	LocatedOwner(const LocatedOwner &p) : control(p.control), owns(p.owns) { if (owns) { ++control->live; } }
	~LocatedOwner() {
		if (owns) {
			--control->live;
			control->bad_destroys += self != this;
			control->owning_destroys_locked += test_queue_lock_depth != 0;
		}
	}
};
struct AddressSink {
	void borrow(const LocatedOwner &owner) {
		++owner.control->calls; owner.control->bad_calls += owner.self != &owner;
	}
};
template <typename Queue> void address_growth(const char *variant) {
	AddressControl c;
	{
		AddressSink sink; Queue queue;
		for (int i = 0; i < 2048; ++i) { queue.push_internal("located", &sink, &AddressSink::borrow, LocatedOwner(c)); }
		queue.flush();
	}
	outcome(variant, "stable_addresses_beyond_64KiB", c.live == 0 && c.calls == 2048 && c.bad_calls == 0 && c.bad_destroys == 0 && c.owning_destroys_locked == 0,
			",\"calls\":" + std::to_string(c.calls) + ",\"bad_call_addresses\":" + std::to_string(c.bad_calls)
			+ ",\"bad_destroy_addresses\":" + std::to_string(c.bad_destroys) + ",\"live_after\":" + std::to_string(c.live));
}

template <size_t Alignment> struct alignas(Alignment) BigAligned {
	std::array<uint8_t, 4096> data{};
};
struct AlignmentSink {
	int calls = 0, bad = 0;
	template <size_t Alignment> void take(const BigAligned<Alignment> &value) {
		++calls; bad += reinterpret_cast<uintptr_t>(&value) % Alignment != 0;
	}
};

struct Hook {
	void *context;
	void (*enqueue)(void *);
	int calls = 0, locked = 0;
	void run() { ++calls; if (test_queue_lock_depth) { ++locked; } else { enqueue(context); } }
};
struct DestroyPush {
	Hook *hook; bool owns = true;
	explicit DestroyPush(Hook &h) : hook(&h) {}
	DestroyPush(DestroyPush &&p) noexcept : hook(p.hook), owns(std::exchange(p.owns, false)) {}
	DestroyPush(const DestroyPush &) = delete;
	~DestroyPush() { if (owns) { hook->run(); } }
};
struct CopyPush {
	Hook *hook;
	explicit CopyPush(Hook &h) : hook(&h) {}
	CopyPush(const CopyPush &p) : hook(p.hook) { hook->run(); }
};
struct ReentrySink {
	StableQueue *queue;
	std::vector<int> order;
	bool request_stop = false;
	void add(int n) { order.push_back(n); }
	void nested(int n) {
		order.push_back(n);
		if (request_stop) { queue->request_exit(); }
		queue->push_internal("nested", this, &ReentrySink::add, 3);
	}
	void retire(const DestroyPush &) { order.push_back(2); }
	void copied(const CopyPush &) { order.push_back(2); }
};
void push_four(void *p) { auto &s = *static_cast<ReentrySink *>(p); s.queue->push_internal("destructor", &s, &ReentrySink::add, 4); }
void push_one(void *p) { auto &s = *static_cast<ReentrySink *>(p); s.queue->push_internal("constructor", &s, &ReentrySink::add, 1); }

struct BytesSink {
	Vector<uint8_t> retained;
	void take(Vector<uint8_t> bytes) { retained = std::move(bytes); }
};
struct NumberSink {
	uint64_t sum = 0, calls = 0;
	void add(uint64_t n) { sum += n; ++calls; }
};
struct BurstSink {
	StableQueue *queue; int calls = 0;
	void child(int) { ++calls; }
	void grow() {
		++calls;
		for (int i = 0; i < 8192; ++i) { queue->push_internal("growth", this, &BurstSink::child, i); }
	}
};

void stable_cases() {
	const uint64_t before = Memory::get_mem_usage();
	{
		AlignmentSink sink; StableQueue queue;
		queue.push_internal("align64", &sink, &AlignmentSink::take<64>, BigAligned<64>{});
		queue.push_internal("align256", &sink, &AlignmentSink::take<256>, BigAligned<256>{});
		queue.flush();
		outcome("stable", "large_4096_byte_commands_align64_and256", sink.calls == 2 && sink.bad == 0);
	}
	{
		ReentrySink sink{nullptr, {}, true}; Hook hook{&sink, push_four}; StableQueue queue; sink.queue = &queue;
		queue.push_internal("parent", &sink, &ReentrySink::nested, 1);
		queue.push_internal("retire", &sink, &ReentrySink::retire, DestroyPush(hook));
		const bool keep_running = queue.wait_and_flush();
		outcome("stable", "call_and_final_destroy_reenter_fifo_and_stop_drain", !keep_running && sink.order == std::vector<int>({1, 2, 3, 4}) && hook.calls == 1 && hook.locked == 0);
		queue.reset(); sink.order.clear();
		queue.push_internal("restart", &sink, &ReentrySink::add, 5);
		outcome("stable", "reset_after_stop_restarts", queue.wait_and_flush() && sink.order == std::vector<int>({5}));
		queue.request_exit();
		outcome("stable", "empty_stop_returns_without_waiting", !queue.wait_and_flush());
	}
	{
		ReentrySink sink{nullptr, {}, false}; Hook hook{&sink, push_one}; CopyPush caller(hook); StableQueue queue; sink.queue = &queue;
		queue.push_internal("copy", &sink, &ReentrySink::copied, caller); queue.flush();
		outcome("stable", "construction_reenters_before_outer_command_is_published", sink.order == std::vector<int>({1, 2}) && hook.calls == 1 && hook.locked == 0);
	}
	{
		ReentrySink sink{nullptr, {}, false}; StableQueue queue; sink.queue = &queue;
		queue.push_internal("pending", &sink, &ReentrySink::add, 1); queue.request_exit(); queue.reset();
		queue.push_internal("restarted", &sink, &ReentrySink::add, 2);
		outcome("stable", "quiescent_reset_drains_accepted_work_instead_of_dropping", queue.wait_and_flush() && sink.order == std::vector<int>({1, 2}));
	}
	{
		BurstSink sink{nullptr}; StableQueue queue; sink.queue = &queue;
		queue.push_internal("grow", &sink, &BurstSink::grow); queue.request_exit();
		outcome("stable", "exit_drains_growth_enqueued_by_inflight_command", !queue.wait_and_flush() && sink.calls == 8193);
	}
	{
		BytesSink sink; StableQueue queue; Vector<uint8_t> caller; caller.resize(65536); caller.write[0] = 42;
		queue.push_internal("bytes", &sink, &BytesSink::take, caller); queue.flush();
		const bool shared = caller.ptr() == sink.retained.ptr() && caller[0] == 42;
		sink.retained.write[0] = 17;
		outcome("stable", "actual_Godot_Vector_PackedByteArray_move_retention_COW", shared && caller[0] == 42 && sink.retained[0] == 17 && caller.ptr() != sink.retained.ptr());
	}
	{
		NumberSink sink;
		{ StableQueue queue; for (int i = 0; i < 16; ++i) { queue.push_internal("destructor drain", &sink, &NumberSink::add, uint64_t(i)); } }
		outcome("stable", "queue_destructor_drains_pending_commands", sink.calls == 16 && sink.sum == 120);
	}
	{
		NumberSink sink; StableQueue queue;
		std::thread consumer([&]() { while (queue.wait_and_flush()) {} });
		std::vector<std::thread> producers;
		constexpr uint64_t each = 4096, count = 4 * each;
		for (uint64_t producer = 0; producer < 4; ++producer) {
			producers.emplace_back([&, producer]() { for (uint64_t i = 0; i < each; ++i) { queue.push_internal("producer", &sink, &NumberSink::add, producer * each + i); } });
		}
		for (auto &producer : producers) { producer.join(); }
		queue.request_exit(); consumer.join();
		outcome("stable", "four_internal_producers_one_consumer_stop_after_producers_join", sink.calls == count && sink.sum == count * (count - 1) / 2,
				",\"delivered\":" + std::to_string(sink.calls));
	}
	outcome("stable", "actual_Godot_normal_allocated_bytes_return_to_baseline", Memory::get_mem_usage() == before,
			",\"before\":" + std::to_string(before) + ",\"after\":" + std::to_string(Memory::get_mem_usage()));
}

template <typename Queue> void bench(const char *variant, int round, uint64_t batch_size) {
	constexpr uint64_t count = 120000;
	NumberSink sink;
	const auto baseline_bytes = Memory::get_mem_usage();
	Queue queue;
	uint64_t first_batch_bytes = 0;
	const auto locks_before = test_queue_lock_calls;
	const auto began = std::chrono::steady_clock::now();
	for (uint64_t i = 0; i < count;) {
		const uint64_t end = std::min(count, i + batch_size);
		for (; i < end; ++i) { queue.push_internal("small", &sink, &NumberSink::add, i); }
		if (!first_batch_bytes) { first_batch_bytes = Memory::get_mem_usage() - baseline_bytes; }
		queue.flush();
	}
	const auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - began).count();
	const bool correct = sink.calls == count && sink.sum == count * (count - 1) / 2;
	outcome(variant, "small_command_ABBA_throughput", correct,
			",\"round\":" + std::to_string(round) + ",\"batch_size\":" + std::to_string(batch_size)
			+ ",\"commands\":" + std::to_string(count) + ",\"elapsed_ns\":" + std::to_string(ns)
			+ ",\"queue_mutex_acquisitions\":" + std::to_string(test_queue_lock_calls - locks_before)
			+ ",\"first_batch_Godot_normal_payload_bytes\":" + std::to_string(first_batch_bytes));
}

int main(int argc, char **argv) {
	if (argc != 2) { return 2; }
	if (std::strcmp(argv[1], "original") == 0) {
		run<baseline::SimpleCommandQueue>("original"); address_growth<baseline::SimpleCommandQueue>("original");
	} else if (std::strcmp(argv[1], "stable") == 0) {
		run<StableQueue>("stable"); address_growth<StableQueue>("stable"); stable_cases();
	} else if (std::strcmp(argv[1], "benchmark") == 0) {
		for (uint64_t batch : {1, 64, 1024}) {
			bench<baseline::SimpleCommandQueue>("original", 0, batch);
			bench<StableQueue>("stable", 1, batch);
			bench<StableQueue>("stable", 2, batch);
			bench<baseline::SimpleCommandQueue>("original", 3, batch);
		}
	} else { return 2; }
	return failed ? 1 : 0;
}
