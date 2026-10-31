#include "thread_local_identity_values.h"

std::atomic<std::uint64_t> ThreadIdentityFixture::counter{1};
thread_local std::uint64_t ThreadIdentityFixture::caller_id =
		ThreadIdentityFixture::counter.fetch_add(1, std::memory_order_relaxed) + 1;
