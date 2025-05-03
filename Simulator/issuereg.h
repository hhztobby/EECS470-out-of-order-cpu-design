#pragma once

#include <bitset>
#include <cassert>
#include "fu.h"
#include "instruction.h"

namespace cpu {
	class IssueReg {
	public:
		void onCycleStart() {
			avails.reset();
			brResPacket = {};
		}
		void reset() {
			issInsts = {};
			exInsts = {};
			onCycleStart();
		}
		void onBrRes(const BrResPacket& packet) {
			brResPacket = packet;
			for (int i = 0; i < NUM_FU; i++) {
				if (packet.state == BrResState::hit) {
					if (exInsts[i].valid) {
						exInsts[i].bmask.clearBit(packet.bindex);
					}
				}
				else if (packet.state == BrResState::mis) {
					if (exInsts[i].valid && exInsts[i].bmask.hasSharedBit(packet.bindex)) {
						exInsts[i].valid = 0;
					}
				}
			}
		}
		std::array<ExInst, NUM_FU> getExInsts() const {
			return exInsts;
		}
		void recFuAvails(std::bitset<NUM_FU> fuAvails, std::bitset<NUM_FU> fuAccepted) {
			avails = fuAvails;
			for (int i = 0; i < NUM_FU; i++) {
				if (fuAccepted[i]) {
					issInsts[i].valid = 0;
				}
			}
		}
		FUAvailsPacket getIssAvails() const {
			FUAvailsPacket ret{};
			for (int i = 0; i < NUM_FU; i++) {
				if (i > NUM_ALU && i < NUM_ALU + NUM_MUL) {
					ret.avails[i] = avails[i] || !issInsts[i].valid;
				}
				else {
					ret.avails[i] = avails[i];
				}
			}
			return ret;
		}
		void recIssueInsts(const IssuePacket& packet) {
			for (int i = 0; i < NUM_FU; i++) {
				if (i > NUM_ALU && i < NUM_ALU + NUM_MUL) {
					if (packet.insts[i].valid) {
						assert(!issInsts[i].valid);
						issInsts[i] = packet.insts[i];
					}
				}
				else {
					issInsts[i] = packet.insts[i];
				}
			}
			for (int i = 0; i < NUM_FU; i++) {
				if (packet.insts[i].valid) {
					// assert(avails[i]);
					if (brResPacket.state == BrResState::mis) {
						assert(!packet.insts[i].bmask.hasSharedBit(brResPacket.bindex));
					}
					else if (brResPacket.state == BrResState::hit) {
						assert(!packet.insts[i].bmask.hasSharedBit(brResPacket.bindex));
						assert(packet.insts[i].bindex != brResPacket.bindex);
					}
				}
			}
		}
		std::array<Tag, 2 * NUM_FU> getIssSrcTags() const {
			std::array<Tag, 2 * NUM_FU> ret{};
			for (int i = 0; i < NUM_FU; i++) {
				if (issInsts[i].valid) {
					ret[i * 2 + 0] = issInsts[i].inst.src1.tag;
					ret[i * 2 + 1] = issInsts[i].inst.src2.tag;
				}
			}
			return ret;
		}
		void recData(const std::array<Data, 2 * NUM_FU>& cdbData, 
			const std::array<Data, 2 * NUM_FU>& prfData) {
			exInsts.fill({});
			for (int i = 0; i < NUM_FU; i++) {
				if (issInsts[i].valid) {
					exInsts[i].valid = 1;
					exInsts[i].inst = issInsts[i].inst.inst;
					exInsts[i].pc = issInsts[i].inst.pc;
					exInsts[i].npc = issInsts[i].inst.npc;
					exInsts[i].dst = issInsts[i].inst.dst;
					exInsts[i].opa = issInsts[i].inst.opa;
					exInsts[i].opb = issInsts[i].inst.opb;
					exInsts[i].aluFunc = issInsts[i].inst.aluFunc;
					exInsts[i].hasDst = issInsts[i].inst.hasDst;
					exInsts[i].isCondBr = issInsts[i].inst.isCondBr;
					exInsts[i].bindex = issInsts[i].bindex;
					exInsts[i].bmask = issInsts[i].bmask;
					assert(!(issInsts[i].inst.isCondBr && issInsts[i].inst.isUncondBr));
					exInsts[i].predictedTaken = issInsts[i].predictedTaken;
					if (issInsts[i].earlyTag1) {
						exInsts[i].src1 = cdbData[i * 2 + 0];
					}
					else {
						exInsts[i].src1 = prfData[i * 2 + 0];
					}
					if (issInsts[i].earlyTag2) {
						exInsts[i].src2 = cdbData[i * 2 + 1];
					}
					else {
						exInsts[i].src2 = prfData[i * 2 + 1];
					}
				}
			}
		}
		
	private:
		BrResPacket brResPacket{};
		std::bitset<NUM_FU> avails{ 0 }; // combinational
		std::array<IssuedInst, NUM_FU> issInsts{};
		std::array<ExInst, NUM_FU> exInsts{};
	};
}