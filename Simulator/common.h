#pragma once

#include <iostream>
#include <fstream>
#include <filesystem>
#include <cassert>

namespace cpu {
	inline constexpr int N = 2;
	namespace rs {
		inline constexpr int NUM_RS_ENTRIES = 8;
	}
	inline constexpr uint32_t BRANCH_STACK_SIZE = 4;

	inline constexpr uint32_t MUL_STAGES = 3; // num of registers, actual stage = this + 1
	inline constexpr int NUM_ALU = 3;
	inline constexpr int NUM_MUL = 1;
	inline constexpr int NUM_MEM = 1;
	inline constexpr int NUM_BR = 1;
	inline constexpr int NUM_HALT = 1;
	inline constexpr int NUM_FU = NUM_ALU + NUM_MUL + NUM_MEM + NUM_BR + NUM_HALT;
}

template <typename T>
concept HasGetRegister = requires(T t) {
	{ t.streamRegister() } -> std::same_as<std::string>;
};

class LOG {
public:
	static inline constexpr bool fetch = 1;
	static inline constexpr bool dispatch = 1;
	static inline constexpr bool fl = 1;
	static inline constexpr bool mt = 1;
	static inline constexpr bool rs = 1;
	static inline constexpr bool issueReg = 1;
	static inline constexpr bool fu = 1;
	static inline constexpr bool cdb = 1;
	static inline constexpr bool rob = 1;
	enum class LogLevel {
		none,
		simple,
		verbose
	};
	static inline LogLevel logLevel{ LogLevel::verbose };
	static void log(LogLevel level, const std::string& msg);
	LOG();
	~LOG();
	void logWb(uint32_t pc, uint32_t inst, uint32_t regIdx, uint32_t data);
	static LOG& getInstance();

	void logRegister(const std::string& msg);
	template<HasGetRegister  T>
	void logRegister(T module) {
		regDebugFile << module.streamRegister();
	}
private:
	std::filesystem::path wbPath{};
	std::filesystem::path regDebugPath{};
	std::fstream wbFile{};
	std::fstream regDebugFile{};
};