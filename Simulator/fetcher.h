#pragma once

#include <string_view>
#include <fstream>
#include <filesystem>
#include <stdexcept>
#include <format>
#include <string>
#include <array>
#include "instruction.h"
#include "common.h"
#include <iostream>

namespace fs = std::filesystem;

namespace cpu {

	class Parser {
	public:
		static std::vector<Inst> readHexInstMem(std::string_view path, uint32_t hexPerLine = 16) {
			std::vector<Inst> buffer;
			fs::path file_path(path);
			if (!fs::exists(file_path)) {
				std::cout << "File does not exist: " << std::filesystem::absolute(file_path).string() << std::endl;
				assert(0);
			}
			std::ifstream file(file_path);
			std::string hexInstr;
			// Read each 8-character (32-bit) instruction from the file
			while (file >> hexInstr) {
				if (hexInstr.length() != hexPerLine) { // Ensure correct format
					std::cout << "Invalid file format. Expected " << hexPerLine << ", got " << hexInstr.length() << std::endl;
					assert(0);
				}
				for (int i = static_cast<int>(hexInstr.length()); i >= 8 ; i -= 8) {
					buffer.emplace_back(hexInstr.substr(i - 8, 8));
				}
			}
			return buffer;
		}
	};

	class Fetcher {
	public:
		void readIntoBuffer(std::string_view path) {
			buffer = Parser::readHexInstMem(path);
		}
		void reset() {
			pc = 0;
			correct_pc = 0;
			mispredicted = 0;
		}
		void onCycleStart() {
			if (mispredicted) {
				pc = correct_pc;
			}
			mispredicted = 0;
		}
		void onBranchMispredict(pc_t target_pc) {
			assert(target_pc.to_ulong() % 4 == 0);
			mispredicted = 1;
			correct_pc = target_pc.to_ulong();
			if constexpr (LOG::fetch) {
				LOG::log(LOG::LogLevel::simple, std::format("[fetch]: mispredicted acknowledged, move to target_pc/4 = {}", target_pc.to_ulong()/4));
			}
		}
		std::array<FetchInst, N> getFetchedInsts() {
			std::array<FetchInst, N> ret{};
			if (mispredicted) {
				if constexpr (LOG::fetch) {
					LOG::log(LOG::LogLevel::verbose, std::format("[fetch]: since mispredicted, no instruction fetched"));
				}
				return ret;
			}
			uint32_t idx = pc / 4;
			for (int i = 0; i < N; i++) {
				if (idx >= buffer.size()) break;
				ret[i] = FetchInst{
					.valid = 1,
					.inst = buffer[idx + i],
					.pc = pc + 4 * i,
					.npc = pc + 4 + 4 * i,
					.predictedTaken = 0,
				};
			}
			return ret;
		}
		void recDispatcherAccepted(const std::bitset<N>& accepted) {
			if (mispredicted) {
				assert(accepted.none());
			}
			for (int i = 0; i < N; i++) {
				if (accepted[i]) {
					pc += 4;
				}
			}
			if constexpr (LOG::fetch) {
				LOG::log(LOG::LogLevel::verbose, std::format("[fetch]: instructions accepted by dispatcher: {}", accepted.to_string()));
			}
		}
		std::vector<Inst> buffer;
	private:
		bool mispredicted = 0;
		uint32_t pc{ 0 };
		uint32_t correct_pc{ 0 };
	};
	
}