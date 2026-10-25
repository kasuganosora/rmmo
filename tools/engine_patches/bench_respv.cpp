#include "re-spirv.h"
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <algorithm>
#include <string>
#include <thread>
#include <atomic>

using Clock = std::chrono::steady_clock;
double millis(Clock::time_point start) { return std::chrono::duration<double,std::milli>(Clock::now()-start).count(); }
struct Input {std::string name; std::vector<uint8_t> data;};
int main(int argc,char **argv) {
    if(argc!=4 && argc!=5)return 2;
    std::vector<Input> inputs;
    for(auto &entry:std::filesystem::directory_iterator(argv[1])) {
        if(entry.path().extension()!=".spv")continue;
        std::ifstream f(entry.path(),std::ios::binary);
        inputs.push_back({entry.path().filename().string(),std::vector<uint8_t>(std::istreambuf_iterator<char>(f),{})});
    }
    std::sort(inputs.begin(),inputs.end(),[](const auto &a,const auto &b){return a.name<b.name;});
    if(inputs.empty())return 3;
    std::filesystem::create_directories(argv[2]);
    int rounds=std::stoi(argv[3]);
    for(int round=0;round<rounds;round++) {
        for(auto &input:inputs) {
            auto start=Clock::now();
            respv::Shader shader(input.data.data(),input.data.size(),true);
            double parse_ms=millis(start);
            if(shader.empty())return 4;
            std::vector<uint8_t> optimized;
            start=Clock::now();
            if(!respv::Optimizer::run(shader,nullptr,0,optimized))return 5;
            double optimize_ms=millis(start);
            if(round==0) {
                std::ofstream out(std::filesystem::path(argv[2])/(input.name+".out"),std::ios::binary);
                out.write(reinterpret_cast<char*>(optimized.data()),optimized.size());
            }
            std::cout<<input.name<<","<<round<<","<<input.data.size()<<","<<shader.instructions.size()<<","<<optimized.size()<<","<<parse_ms<<","<<optimize_ms<<"\n";
        }
    }
    if(argc==5) {
        std::atomic<int> failures{0};
        std::vector<std::thread> workers;
        for(int worker=0;worker<std::stoi(argv[4]);worker++)workers.emplace_back([&,worker]() {
            for(int i=0;i<int(inputs.size())*4;i++) {
                auto &input=inputs[(i+worker*7)%inputs.size()];
                respv::Shader shader(input.data.data(),input.data.size(),true);
                std::vector<uint8_t> actual;
                if(shader.empty() || !respv::Optimizer::run(shader,nullptr,0,actual)) { failures++;continue; }
                std::ifstream file(std::filesystem::path(argv[2])/(input.name+".out"),std::ios::binary);
                std::vector<uint8_t> expected(std::istreambuf_iterator<char>(file),{});
                if(actual!=expected)failures++;
            }
        });
        for(auto &worker:workers)worker.join();
        std::cerr<<"parallel_failures="<<failures<<" checks="<<std::stoi(argv[4])*inputs.size()*4<<"\n";
        if(failures)return 6;
    }
    return 0;
}
