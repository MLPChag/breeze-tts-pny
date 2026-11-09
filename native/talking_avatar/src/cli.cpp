#include "core.h"
#include <nlohmann/json.hpp>
#include <chrono>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
static std::vector<uint8_t> read(const char*p){std::ifstream f(p,std::ios::binary);if(!f)throw std::runtime_error("Cannot open input");return {std::istreambuf_iterator<char>(f),{}};}
int main(int argc,char**argv){try{
    if(argc<6)throw std::runtime_error("Usage: cli MODEL INPUT RATE CHUNK s16|f32|raw16");
    auto model=talking_avatar::Model::load(read(argv[1]));auto bytes=read(argv[2]);const int rate=std::stoi(argv[3]),chunk=std::stoi(argv[4]);
    if(chunk<=0)throw std::runtime_error("Invalid chunk");
    std::string mode=argv[5];std::vector<float> samples;
    if(mode=="s16"){if(bytes.size()%2)throw std::runtime_error("Odd PCM");for(size_t i=0;i<bytes.size();i+=2)samples.push_back(int16_t(uint16_t(bytes[i])|uint16_t(bytes[i+1])<<8)/32768.0f);}
    else {if(bytes.size()%4)throw std::runtime_error("Bad float PCM");samples.resize(bytes.size()/4);std::memcpy(samples.data(),bytes.data(),bytes.size());}
    nlohmann::json events=nlohmann::json::array(),frames=nlohmann::json::array();auto start=std::chrono::steady_clock::now();
    if(mode=="raw16"){
        talking_avatar::Stream stream(model);for(size_t i=0;i<samples.size();i+=chunk)stream.push(samples.data()+i,std::min(size_t(chunk),samples.size()-i),[&](int id){frames.push_back(id);});
    }else{
        talking_avatar::Detector detector(model,rate,[&](talking_avatar::Event e){if(e.seconds>=0&&e.seconds<double(samples.size())/rate)events.push_back({{"id",e.id},{"t",e.seconds},{"value",std::string(1,talking_avatar::pony_viseme(e.id))}});});
        for(size_t i=0;i<samples.size();i+=chunk) {
            detector.push(samples.data()+i,std::min(size_t(chunk),samples.size()-i));
        }
        detector.finish();
    }
    std::cout<<nlohmann::json{{"events",events},{"frames",frames},{"compute_ms",std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count()}}.dump()<<'\n';return 0;
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}
