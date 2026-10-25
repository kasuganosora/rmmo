#include "re-spirv.h"
#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <string>
#include <vector>
using Clock=std::chrono::steady_clock;
using Ns=std::chrono::nanoseconds;
struct Input {std::string name;std::vector<uint8_t> data;};
struct Packet {std::vector<respv::Shader> stages;};
size_t capacity_bytes(const respv::Shader &s) { return s.inlinedSpirvWords.capacity()*sizeof(s.inlinedSpirvWords[0])+s.instructions.capacity()*sizeof(s.instructions[0])+s.instructionAdjacentListIndices.capacity()*sizeof(s.instructionAdjacentListIndices[0])+s.instructionInDegrees.capacity()*sizeof(s.instructionInDegrees[0])+s.instructionOutDegrees.capacity()*sizeof(s.instructionOutDegrees[0])+s.instructionOrder.capacity()*sizeof(s.instructionOrder[0])+s.blocks.capacity()*sizeof(s.blocks[0])+s.blockPreOrderIndices.capacity()*sizeof(s.blockPreOrderIndices[0])+s.blockPostOrderIndices.capacity()*sizeof(s.blockPostOrderIndices[0])+s.functions.capacity()*sizeof(s.functions[0])+s.variableOrder.capacity()*sizeof(s.variableOrder[0])+s.results.capacity()*sizeof(s.results[0])+s.specializations.capacity()*sizeof(s.specializations[0])+s.decorations.capacity()*sizeof(s.decorations[0])+s.phis.capacity()*sizeof(s.phis[0])+s.loopHeaders.capacity()*sizeof(s.loopHeaders[0])+s.listNodes.capacity()*sizeof(s.listNodes[0]); }
void compact(respv::Shader &s) {
 if(s.inlinedSpirvWords.capacity()!=s.inlinedSpirvWords.size())decltype(s.inlinedSpirvWords)(s.inlinedSpirvWords.begin(),s.inlinedSpirvWords.end()).swap(s.inlinedSpirvWords);
 if(s.instructions.capacity()!=s.instructions.size())decltype(s.instructions)(s.instructions.begin(),s.instructions.end()).swap(s.instructions);
 if(s.instructionAdjacentListIndices.capacity()!=s.instructionAdjacentListIndices.size())decltype(s.instructionAdjacentListIndices)(s.instructionAdjacentListIndices.begin(),s.instructionAdjacentListIndices.end()).swap(s.instructionAdjacentListIndices);
 if(s.instructionInDegrees.capacity()!=s.instructionInDegrees.size())decltype(s.instructionInDegrees)(s.instructionInDegrees.begin(),s.instructionInDegrees.end()).swap(s.instructionInDegrees);
 if(s.instructionOutDegrees.capacity()!=s.instructionOutDegrees.size())decltype(s.instructionOutDegrees)(s.instructionOutDegrees.begin(),s.instructionOutDegrees.end()).swap(s.instructionOutDegrees);
 if(s.instructionOrder.capacity()!=s.instructionOrder.size())decltype(s.instructionOrder)(s.instructionOrder.begin(),s.instructionOrder.end()).swap(s.instructionOrder);
 if(s.blocks.capacity()!=s.blocks.size())decltype(s.blocks)(s.blocks.begin(),s.blocks.end()).swap(s.blocks);
 if(s.blockPreOrderIndices.capacity()!=s.blockPreOrderIndices.size())decltype(s.blockPreOrderIndices)(s.blockPreOrderIndices.begin(),s.blockPreOrderIndices.end()).swap(s.blockPreOrderIndices);
 if(s.blockPostOrderIndices.capacity()!=s.blockPostOrderIndices.size())decltype(s.blockPostOrderIndices)(s.blockPostOrderIndices.begin(),s.blockPostOrderIndices.end()).swap(s.blockPostOrderIndices);
 if(s.functions.capacity()!=s.functions.size())decltype(s.functions)(s.functions.begin(),s.functions.end()).swap(s.functions);
 if(s.variableOrder.capacity()!=s.variableOrder.size())decltype(s.variableOrder)(s.variableOrder.begin(),s.variableOrder.end()).swap(s.variableOrder);
 if(s.results.capacity()!=s.results.size())decltype(s.results)(s.results.begin(),s.results.end()).swap(s.results);
 if(s.specializations.capacity()!=s.specializations.size())decltype(s.specializations)(s.specializations.begin(),s.specializations.end()).swap(s.specializations);
 if(s.decorations.capacity()!=s.decorations.size())decltype(s.decorations)(s.decorations.begin(),s.decorations.end()).swap(s.decorations);
 if(s.phis.capacity()!=s.phis.size())decltype(s.phis)(s.phis.begin(),s.phis.end()).swap(s.phis);
 if(s.loopHeaders.capacity()!=s.loopHeaders.size())decltype(s.loopHeaders)(s.loopHeaders.begin(),s.loopHeaders.end()).swap(s.loopHeaders);
 if(s.listNodes.capacity()!=s.listNodes.size())decltype(s.listNodes)(s.listNodes.begin(),s.listNodes.end()).swap(s.listNodes);
}
int main(int argc,char **argv) {
 if(argc!=5)return 2;
 bool move=std::string(argv[2])!="copy";bool tight=std::string(argv[2])=="compact";int rounds=std::stoi(argv[3]);
 std::vector<Input> inputs;
 for(auto &entry:std::filesystem::directory_iterator(argv[1]))if(entry.path().extension()==".spv") {
  std::ifstream f(entry.path(),std::ios::binary);inputs.push_back({entry.path().filename().string(),{std::istreambuf_iterator<char>(f),{}}});
 }
 std::sort(inputs.begin(),inputs.end(),[](const auto &a,const auto &b){return a.name<b.name;});
 if(inputs.empty())return 3;std::filesystem::create_directories(argv[4]);
 int checks=0;uint64_t moved_buffers=0;size_t bytes=0;
 for(int round=0;round<rounds;round++) {
  int64_t parse_ns=0,transfer_ns=0,release_ns=0;
  for(size_t i=0;i<inputs.size();i+=2) {
   Packet info;info.stages.reserve(2);
   for(size_t j=i;j<std::min(i+2,inputs.size());j++) {
    auto t=Clock::now();respv::Shader shader(inputs[j].data.data(),inputs[j].data.size(),true);
    parse_ns+=std::chrono::duration_cast<Ns>(Clock::now()-t).count();if(shader.empty())return 4;
    auto *owned=shader.instructions.data();t=Clock::now();
    if(move) {if(tight) {compact(shader);owned=shader.instructions.data();}info.stages.push_back(std::move(shader));}else info.stages.push_back(shader);
    transfer_ns+=std::chrono::duration_cast<Ns>(Clock::now()-t).count();
    if(move) {if(info.stages.back().instructions.data()!=owned)return 5;moved_buffers++;}
   }
   auto target=std::make_unique<Packet>();auto *owned=info.stages.front().instructions.data();
   auto t=Clock::now();if(move)*target=std::move(info);else *target=info;
   transfer_ns+=std::chrono::duration_cast<Ns>(Clock::now()-t).count();
   if(move) {if(target->stages.front().instructions.data()!=owned)return 6;moved_buffers++;}
   if(round==0)for(size_t j=0;j<target->stages.size();j++) {
    bytes+=capacity_bytes(target->stages[j]);
    std::vector<uint8_t> output;if(!respv::Optimizer::run(target->stages[j],nullptr,0,output))return 7;
    std::ofstream f(std::filesystem::path(argv[4])/(inputs[i+j].name+".out"),std::ios::binary);f.write(reinterpret_cast<char*>(output.data()),output.size());checks++;
   }
   t=Clock::now();target.reset();info.stages.clear();release_ns+=std::chrono::duration_cast<Ns>(Clock::now()-t).count();
  }
  std::cout<<round<<","<<parse_ns<<","<<transfer_ns<<","<<release_ns<<"\n";
 }
 std::cerr<<"capacity_bytes="<<bytes<<" ";
 std::cerr<<"checks="<<checks<<" moved_buffers="<<moved_buffers<<"\n";
}
