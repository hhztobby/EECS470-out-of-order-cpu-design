#pragma once

#include <bitset>
#include <array>
#include <cstdint>
#include <string>
#include <cassert>

#include "register.h"
#include "isa.h"
#include "branch.h"

namespace cpu {

	typedef std::bitset<32> pc_t;
	using RegIdx = std::bitset<5>;

	struct Inst {
		friend class Decoder;
		friend struct DecodedInst;
		Inst() = default;
		Inst(std::string hex) {
			assert(hex.length() == 8);
			data = std::bitset<32>(std::stoul(hex, nullptr, 16));
		}
		std::bitset<32> data;
		RegIdx getRd() const {
			return ((data.to_ulong() >> 7) & 0b11111);
		}
		RegIdx getRs1() const {
			return ((data.to_ulong() >> 15) & 0b11111);
		}
		RegIdx getRs2() const {
			return ((data.to_ulong() >> 20) & 0b11111);
		}
		uint32_t getFunct3() const {
			return ((data.to_ulong() >> 12) & 0b111);
		}
		Data getIImm() const {
			int32_t imm = static_cast<int32_t>(data.to_ulong()) >> 20; // Sign extend from bit 31
			return Data(static_cast<uint32_t>(imm));
		}

		Data getSImm() const {
			int32_t imm = ((static_cast<int32_t>(data.to_ulong()) >> 25) << 5) | ((data.to_ulong() >> 7) & 0x1F);
			imm = (imm << 20) >> 20; // Sign extend
			return Data(static_cast<uint32_t>(imm));
		}

		Data getBImm() const {
			int32_t imm = ((data.to_ulong() >> 31) << 12) | (((data.to_ulong() >> 7) & 1) << 11) |
				(((data.to_ulong() >> 25) & 0x3F) << 5) | (((data.to_ulong() >> 8) & 0xF) << 1);
			imm = (imm << 19) >> 19; // Sign extend
			return Data(static_cast<uint32_t>(imm));
		}

		Data getUImm() const {
			uint32_t imm = data.to_ulong() & 0xFFFFF000; // Upper 20 bits, lower 12 are zeroed
			return Data(imm);
		}

		Data getJImm() const {
			int32_t imm = ((data.to_ulong() >> 31) << 20) | (((data.to_ulong() >> 12) & 0xFF) << 12) |
				(((data.to_ulong() >> 20) & 1) << 11) | (((data.to_ulong() >> 21) & 0x3FF) << 1);
			imm = (imm << 11) >> 11; // Sign extend
			return Data(static_cast<uint32_t>(imm));
		}
		static bool isRType(std::bitset<32> data, isa::Opcode op, isa::Funct3 fu3, isa::Funct7 fu7);
		static bool isIType(std::bitset<32> data, isa::Opcode op, isa::Funct3 fu3);
		static bool isSType(std::bitset<32> data, isa::Opcode op, isa::Funct3 fu3);
		static bool isUType(std::bitset<32> data, isa::Opcode op);
		bool isRType(isa::Opcode op, isa::Funct3 fu3, isa::Funct7 fu7) const;
		bool isIType(isa::Opcode op, isa::Funct3 fu3) const;
		bool isSType(isa::Opcode op, isa::Funct3 fu3) const;
		bool isUType(isa::Opcode op) const;
		bool isLUI() const {
			return isUType(isa::eOpcode::LUI_OP);
		}
		bool isAUIPC() const {
			return isUType(isa::eOpcode::AUIPC_OP);
		}
		bool isJAL() const {
			return isUType(isa::eOpcode::JAL_OP);
		}
		bool isJALR() const {
			return isIType(isa::eOpcode::JALR_OP, 0b000);
		}
		bool isBEQ() const {
			return isSType(isa::eOpcode::BRANCH, 0b000);
		}
		bool isBNE() const {
			return isSType(isa::eOpcode::BRANCH, 0b001);
		}
		bool isBLT() const {
			return isSType(isa::eOpcode::BRANCH, 0b100);
		}
		bool isBGE() const {
			return isSType(isa::eOpcode::BRANCH, 0b101);
		}
		bool isBLTU() const {
			return isSType(isa::eOpcode::BRANCH, 0b110);
		}
		bool isBGEU() const {
			return isSType(isa::eOpcode::BRANCH, 0b111);
		}

		bool isLB() const {
			return isIType(isa::eOpcode::LOAD, 0b000);
		}

		bool isLH() const {
			return isIType(isa::eOpcode::LOAD, 0b001);
		}

		bool isLW() const {
			return isIType(isa::eOpcode::LOAD, 0b010);
		}

		bool isLBU() const {
			return isIType(isa::eOpcode::LOAD, 0b100);
		}

		bool isLHU() const {
			return isIType(isa::eOpcode::LOAD, 0b101);
		}

		bool isSB() const {
			return isSType(isa::eOpcode::STORE, 0b000);
		}

		bool isSH() const {
			return isSType(isa::eOpcode::STORE, 0b001);
		}

		bool isSW() const {
			return isSType(isa::eOpcode::STORE, 0b010);
		}

		bool isADDI() const {
			return isIType(isa::eOpcode::OP_IMM, 0b000);
		}

		bool isSLTI() const {
			return isIType(isa::eOpcode::OP_IMM, 0b010);
		}

		bool isSLTIU() const {
			return isIType(isa::eOpcode::OP_IMM, 0b011);
		}

		bool isXORI() const {
			return isIType(isa::eOpcode::OP_IMM, 0b100);
		}

		bool isORI() const {
			return isIType(isa::eOpcode::OP_IMM, 0b110);
		}

		bool isANDI() const {
			return isIType(isa::eOpcode::OP_IMM, 0b111);
		}

		bool isSLLI() const {
			return isRType(isa::eOpcode::OP_IMM, 0b001, 0b0000000);
		}

		bool isSRLI() const {
			return isRType(isa::eOpcode::OP_IMM, 0b101, 0b0000000);
		}

		bool isSRAI() const {
			return isRType(isa::eOpcode::OP_IMM, 0b101, 0b0100000);
		}

		bool isADD() const {
			return isRType(isa::eOpcode::OP, 0b000, 0b0000000);
		}

		bool isSUB() const {
			return isRType(isa::eOpcode::OP, 0b000, 0b0100000);
		}

		bool isSLL() const {
			return isRType(isa::eOpcode::OP, 0b001, 0b0000000);
		}

		bool isSLT() const {
			return isRType(isa::eOpcode::OP, 0b010, 0b0000000);
		}

		bool isSLTU() const {
			return isRType(isa::eOpcode::OP, 0b011, 0b0000000);
		}

		bool isXOR() const {
			return isRType(isa::eOpcode::OP, 0b100, 0b0000000);
		}

		bool isSRL() const {
			return isRType(isa::eOpcode::OP, 0b101, 0b0000000);
		}

		bool isSRA() const {
			return isRType(isa::eOpcode::OP, 0b101, 0b0100000);
		}

		bool isOR() const {
			return isRType(isa::eOpcode::OP, 0b110, 0b0000000);
		}

		bool isAND() const {
			return isRType(isa::eOpcode::OP, 0b111, 0b0000000);
		}

		/*bool isFENCE() const {
			return isIType(isa::eOpcode::FENCE, 0b000);
		}

		bool isFENCEI() const {
			return isIType(isa::eOpcode::FENCE, 0b001);
		}*/

		bool isMUL() const {
			return isRType(isa::eOpcode::OP, isa::eFunct3::MUL, 0b0000001);
		}

		bool isMULH() const {
			return isRType(isa::eOpcode::OP, isa::eFunct3::MULH, 0b0000001);
		}

		bool isMULHSU() const {
			return isRType(isa::eOpcode::OP, isa::eFunct3::MULHSU, 0b0000001);
		}

		bool isMULHU() const {
			return isRType(isa::eOpcode::OP, isa::eFunct3::MULHU, 0b0000001);
		}

		/*bool isDIV() const {
			return isRType(isa::eOpcode::OP, isa::eFunct3::DIV, 0b0000001);
		}

		bool isDIVU() const {
			return isRType(isa::eOpcode::OP, isa::eFunct3::DIVU, 0b0000001);
		}

		bool isREM() const {
			return isRType(isa::eOpcode::OP, isa::eFunct3::REM, 0b0000001);
		}

		bool isREMU() const {
			return isRType(isa::eOpcode::OP, isa::eFunct3::REMU, 0b0000001);
		}*/

		bool isCSRRW() const {
			return isIType(isa::eOpcode::SYSTEM, isa::eFunct3::CSRRW);
		}
		bool isCSRRS() const {
			return isIType(isa::eOpcode::SYSTEM, isa::eFunct3::CSRRS);
		}
		bool isCSRRC() const {
			return isIType(isa::eOpcode::SYSTEM, isa::eFunct3::CSRRC);
		}
		bool isWFI() const {	
			return data == (0b000100000101 << 20 | 0b0 << 7 | static_cast<uint8_t>(isa::eOpcode::SYSTEM));
		}
	};


	enum class AluOpASel {
		rs1,
		npc,
		pc,
		zero
	};

	enum class AluOpBSel {
		rs2,
		iImm,
		sImm,
		bImm,
		uImm,
		jImm
	};

	enum class AluFunc {
		add,
		sub,
		slt,
		sltu,
		and_,
		or_,
		xor_,
		sll,
		srl,
		sra
	};

	struct FetchInst {
		bool valid = 0;
		Inst inst{};
		pc_t pc{};
		pc_t npc{};
		bool predictedTaken = 0;
		// pc_t predictedTarget{}; // currently we all predict not taken...
	};

	struct DecodedInst {
		Inst inst{}; // original instruction
		pc_t pc{}; // program counter
		pc_t npc{}; // next program counter

		TagPlus src1{}, src2{};
		Tag dst{};
		RegIdx dstRegIdx{};

		AluOpASel opa{};
		AluOpBSel opb{};
		AluFunc aluFunc{};
		// note: even if it has dst, dst reg could still be 0!
		bool hasDst = 0;

		bool rdMem = 0;
		bool wrMem = 0;

		bool isMult = 0;
		bool isCondBr = 0;
		bool isUncondBr = 0;
		bool isHalt = 0;
		bool isIllegal = 0;
		RegIdx getRd() const {
			assert(hasDst);
			return inst.getRd();
		}
		RegIdx getRs1() const {
			assert(opa == AluOpASel::rs1);
			return inst.getRs1();
		}
		RegIdx getRs2() const {
			assert(opb == AluOpBSel::rs2);
			return inst.getRs2();
		}
	};


	struct DispatchInst {
		bool valid = 0;
		DecodedInst decInst{};
		Bmask bmask{};
		Bindex bindex{};
		bool predictedTaken = 0;
	};

	struct IssuedInst {
		bool valid = 0;
		DecodedInst inst{};
		Bindex bindex{};
		Bmask bmask{};
		// affected by early tag broadcast
		bool earlyTag1 = 0, earlyTag2 = 0;
		bool predictedTaken = 0;
	};

	struct IssuePacket {
		std::array<IssuedInst, NUM_FU> insts{};
	};

	struct ExInst {
		bool valid = 0;
		Inst inst{}; // original instruction
		pc_t pc{}; // program counter
		pc_t npc{}; // next program counter

		// TagPlus src1{}, src2{};
		Data src1{}, src2{};
		Tag dst{};
		// RegIdx dstRegIdx{};

		AluOpASel opa{};
		AluOpBSel opb{};
		AluFunc aluFunc{};

		bool hasDst = 0;
		bool isCondBr = 0;
		Bindex bindex{};
		Bmask bmask{};
		bool predictedTaken = 0;
	};
}

