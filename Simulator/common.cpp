#include "common.h"
#include "rob.h"
#include <iomanip>

extern "C" char* decode_inst(int inst);

void LOG::log(LogLevel level, const std::string& msg) {
    if (level <= logLevel) {
        std::cout << msg << std::endl;
    }
}

LOG::LOG() {
	wbPath = "./wb.txt";
	regDebugPath = "./reg_debug.txt";
	wbFile = std::fstream(wbPath, std::ios::out);
	if (!wbFile.is_open()) {
		std::cout << "Failed to open wb output file" << std::endl;
		assert(0);
	}
	wbFile << "Register writeback output (hexadecimal)\n";
	regDebugFile = std::fstream(regDebugPath, std::ios::out);
	if (!regDebugFile.is_open()) {
		std::cout << "Failed to open register debug output file" << std::endl;
		assert(0);
	}
}
	
LOG::~LOG() {
	std::cout << "wb output written to " << std::filesystem::absolute(wbPath) << std::endl;
	std::cout << "register debug output written to " << std::filesystem::absolute(regDebugPath) << std::endl;
	wbFile.close();
	regDebugFile.close();
}
	
LOG& LOG::getInstance() {
	static LOG instance;
	return instance;
}

void LOG::logRegister(const std::string& msg)
{
	regDebugFile << msg << std::endl;
	regDebugFile.flush();
}

void LOG::logWb(uint32_t pc, uint32_t inst, uint32_t regIdx, uint32_t data) {
	/*
	if (committed_insts[n].reg_idx == `ZERO_REG) begin
                    $fdisplay(wb_fileno, "PC %4x:%-8s| ---", pc, decode_inst(inst));
                end else begin
                    $fdisplay(wb_fileno, "PC %4x:%-8s| r%02d=%-8x",
                              pc,
                              decode_inst(inst),
                              committed_insts[n].reg_idx,
                              committed_insts[n].data);
                end
	*/
    if (!wbFile.is_open()) {
        return; // Ensure the file is open before writing
    }

    wbFile << "PC " << std::hex << std::setw(4) << std::right << std::setfill('0') << pc << ":";

    // Reset fill and format the instruction
    wbFile << std::setw(8) << std::left << std::setfill(' ') << decode_inst(inst);

    wbFile << "| ";  // Proper spacing before the register/data

    if (regIdx == 0) {
        wbFile << "---\n";
    }
    else {
        wbFile << "r" << std::setw(2) << std::setfill('0') << std::right << std::dec << regIdx
            << "=" << std::setw(8) << std::left << std::setfill(' ') << std::hex << data << "\n";
    }

    wbFile.flush();
}
