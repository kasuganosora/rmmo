#include "simple_command_queue_std_compat.h"
#include <iostream>
#include <optional>

namespace baseline {
#include "queue_original.inc"
}
namespace moved {
#include "queue_moved.inc"
}

struct Event {
	const char *action;
	int refs;
	int lock_depth;
};
// Every control block lives outside and longer than ALL queue/argument owners.
// No delete, free, resource callback, thread, or debugger is involved. Negative
// ref counts are just observations; they NEVER deallocate this control block.
struct Control {
	int refs = 0;
	int copies = 0;
	int moves = 0;
	int destroys = 0;
	int moved_from_destroys = 0;
	int owned_destroys_under_lock = 0;
	int last_owner_under_lock = 0;
	int deliveries = 0;
	int minimum_refs = 0;
	std::array<Event, 64> events{};
	size_t event_count = 0;
	void record(const char *action) {
		if (event_count == events.size()) { throw std::logic_error("event capacity"); }
		minimum_refs = std::min(minimum_refs, refs);
		events[event_count++] = {action, refs, test_queue_lock_depth};
	}
};
struct CountedOwner {
	Control *observer;
	bool owns = true;
	explicit CountedOwner(Control &control) : observer(&control) { ++observer->refs; observer->record("construct"); }
	CountedOwner(const CountedOwner &other) : observer(other.observer), owns(other.owns) {
		++observer->copies;
		if (owns) { ++observer->refs; }
		observer->record("copy");
	}
	CountedOwner(CountedOwner &&other) noexcept : observer(other.observer), owns(std::exchange(other.owns, false)) {
		++observer->moves; observer->record("move");
	}
	~CountedOwner() {
		if (owns) {
			++observer->destroys;
			if (test_queue_lock_depth) { ++observer->owned_destroys_under_lock; }
			if (observer->refs == 1 && test_queue_lock_depth) { ++observer->last_owner_under_lock; }
			--observer->refs; observer->record("destroy_owned");
		} else {
			++observer->moved_from_destroys; observer->record("destroy_moved_from");
		}
	}
};
static_assert(alignof(CountedOwner) <= 8, "this extraction test does not test over-aligned payloads");
struct Sink {
	std::optional<CountedOwner> retained;
	void take(CountedOwner owner) { ++owner.observer->deliveries; owner.observer->record("call_by_value"); }
	void borrow(const CountedOwner &owner) { ++owner.observer->deliveries; owner.observer->record("call_const_ref"); }
	void retain(CountedOwner owner) {
		++owner.observer->deliveries; owner.observer->record("call_retain_by_value"); retained.emplace(std::move(owner));
	}
};

int failed = 0;
void emit(const char *variant, const char *name, const Control &c, int after_flush, int expected_after_flush, bool correct) {
	if (!correct) { ++failed; }
	std::cout << "{\"variant\":\"" << variant << "\",\"case\":\"" << name
			  << "\",\"passed\":" << (correct ? "true" : "false")
			  << ",\"after_flush\":" << after_flush << ",\"expected_after_flush\":" << expected_after_flush
			  << ",\"final_refs\":" << c.refs << ",\"minimum_refs\":" << c.minimum_refs
			  << ",\"copies\":" << c.copies << ",\"moves\":" << c.moves
			  << ",\"owned_destroys\":" << c.destroys << ",\"moved_from_destroys\":" << c.moved_from_destroys
			  << ",\"owned_destroys_under_lock\":" << c.owned_destroys_under_lock
			  << ",\"last_owner_under_lock\":" << c.last_owner_under_lock
			  << ",\"deliveries\":" << c.deliveries << ",\"events\":[";
	for (size_t i = 0; i < c.event_count; ++i) {
		if (i) { std::cout << ','; }
		const auto &event = c.events[i];
		std::cout << "{\"action\":\"" << event.action << "\",\"refs\":" << event.refs << ",\"lock_depth\":" << event.lock_depth << '}';
	}
	std::cout << "]}\n";
}
template <typename Queue> void run(const char *variant) {
	{
		Control control; int after_flush = 0;
		{
			CountedOwner caller(control); Sink sink; Queue queue;
			queue.push_internal("take", &sink, &Sink::take, caller); queue.flush();
			after_flush = control.refs;
		}
		emit(variant, "by_value_kept_caller", control, after_flush, 1,
				after_flush == 1 && control.refs == 0 && control.minimum_refs == 0 && control.owned_destroys_under_lock == 0);
	}
	{
		Control control; int after_flush = 0;
		{
			Sink sink; Queue queue;
			queue.push_internal("take", &sink, &Sink::take, CountedOwner(control)); queue.flush();
			after_flush = control.refs;
		}
		emit(variant, "by_value_sole_owner", control, after_flush, 0,
				after_flush == 0 && control.refs == 0 && control.minimum_refs == 0 && control.owned_destroys_under_lock == 0);
	}
	{
		Control control; int after_flush = 0;
		{
			Sink sink; Queue queue;
			queue.push_internal("borrow", &sink, &Sink::borrow, CountedOwner(control)); queue.flush();
			after_flush = control.refs;
		}
		emit(variant, "const_ref_last_owner", control, after_flush, 0,
				after_flush == 0 && control.refs == 0 && control.last_owner_under_lock == 0);
	}
	{
		Control control; int after_flush = 0;
		{
			Sink sink;
			{
				CountedOwner caller(control); Queue queue;
				queue.push_internal("retain", &sink, &Sink::retain, caller); queue.request_exit();
				if (queue.wait_and_flush()) { throw std::logic_error("exit flag ignored"); }
				after_flush = control.refs;
			}
			sink.retained.reset();
		}
		emit(variant, "by_value_retained_after_return", control, after_flush, 2,
				after_flush == 2 && control.refs == 0 && control.minimum_refs == 0 && control.owned_destroys_under_lock == 0);
	}
}
int main(int argc, char **argv) {
	if (argc != 2) { return 2; }
	if (std::strcmp(argv[1], "original") == 0) { run<baseline::SimpleCommandQueue>("original"); }
	else if (std::strcmp(argv[1], "moved") == 0) { run<moved::SimpleCommandQueue>("moved"); }
	else { return 2; }
	return failed ? 1 : 0;
}
