#ifdef NDEBUG
#error Build this contract with assertions enabled.
#endif
#include "drivers/vulkan/rmmo_module_registry.h"
#include <cassert>
#include <atomic>
#include <thread>
#include <vector>
#include <cstdio>
using R=ModuleRegistry<uint64_t>;
int main(){
 std::atomic<int> create_count{0},destroy_count{0};
 auto create=[&](uint64_t &h){h=uint64_t(++create_count);return true;};
 auto destroy=[&](uint64_t){destroy_count++;};
 uint8_t a[]={1,2,3,4},b[]={1,2,3,5};
 {R r(1024,64);uint64_t h1,h2,h3;R::Entry *e1,*e2,*e3;
  assert(r.acquire(a,4,7,create,h1,e1));assert(r.acquire(a,4,7,create,h2,e2));assert(e1==e2&&h1==h2);
  assert(r.acquire(b,4,7,create,h3,e3));assert(e3!=e1&&h3!=h1); // deliberately equal hash
  auto s=r.stats();assert(s.hits==1&&s.created==2&&s.live==2&&s.retained==8);
  r.release(e1,h1,destroy);assert(r.stats().live==2);r.release(e2,h2,destroy);assert(r.stats().live==1);r.release(e3,h3,destroy);assert(r.stats().live==0&&r.stats().retained==0);}
 {R r(4,64);uint64_t h1,h2;R::Entry *e1,*e2;assert(r.acquire(a,4,1,create,h1,e1));assert(r.acquire(b,4,2,create,h2,e2)&&!e2);assert(r.stats().over_cap==1);r.release(e1,h1,destroy);r.release(e2,h2,destroy);assert(r.stats().retained==0);}
 {R r(1024,1);uint64_t h1,h2;R::Entry *e1,*e2;assert(r.acquire(a,4,1,create,h1,e1));assert(r.acquire(b,4,2,create,h2,e2)&&!e2);assert(r.stats().over_cap==1);r.release(e1,h1,destroy);r.release(e2,h2,destroy);assert(r.stats().retained==0);}
 {R r(1024,64);uint64_t owner,partial;R::Entry *e1,*e2,*bad;
  assert(r.acquire(a,4,1,create,owner,e1));assert(r.acquire(a,4,1,create,partial,e2));
  uint64_t failed;assert(!r.acquire(b,4,2,[](uint64_t &){return false;},failed,bad));r.release(e2,partial,destroy);assert(r.stats().live==1);r.release(e1,owner,destroy);assert(r.stats().live==0&&r.stats().failures==1);}
 {R r(1024,64);int before=create_count;std::vector<std::thread> ts;std::vector<R::Entry*> entries(32);std::vector<uint64_t> handles(32);
  for(int i=0;i<32;i++)ts.emplace_back([&,i](){assert(r.acquire(a,4,9,create,handles[i],entries[i]));});
  for(auto &t:ts)t.join();assert(create_count-before==1&&r.stats().hits==31);ts.clear();
  for(int i=0;i<32;i++)ts.emplace_back([&,i](){r.release(entries[i],handles[i],destroy);});
  for(auto &t:ts)t.join();assert(r.stats().live==0&&r.stats().retained==0);}
 {R r(1024,64);uint8_t final[]={9,8,7,6},source[]={4,5,6};R::SourceKey key{source,3,65537,5,1,0};int before=create_count;std::vector<std::thread> ts;std::vector<R::Entry*> entries(32);std::vector<uint64_t> handles(32);
  for(int i=0;i<32;i++)ts.emplace_back([&,i](){assert(r.acquire(final,4,9,create,handles[i],entries[i],&key));});
  for(auto &t:ts)t.join();assert(create_count-before==1 && r.stats().source_hits==31);ts.clear();
  for(int i=0;i<32;i++)ts.emplace_back([&,i](){r.release(entries[i],handles[i],destroy);});
  for(auto &t:ts)t.join();assert(r.stats().live==0 && r.stats().source_retained==0);}
 assert(create_count==destroy_count);std::puts("PASS equal bytes, forced collision, caps, failed creation rollback, concurrent owners, final zero");
}
