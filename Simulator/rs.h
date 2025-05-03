#pragma once

#include <array>
#include <unordered_map>
#include <sstream>
#include <string>

#include "common.h"
#include "branch.h"
#include "instruction.h"
#include "register.h"
#include "fu.h"

namespace cpu {

	namespace rs {

		enum class EntryState {
			EMPTY,
			DISPATCHED
		};

		enum class FuType {
			nop,
			alu,
			mul,
			mem,
			br,
			halt
		};

		struct Entry {
			DecodedInst decInst{};
			EntryState state{};
			FuType fuType{};
			Tag dst{};
			TagPlus src1{}, src2{};
			bool earlyTag1 = 0, earlyTag2 = 0;
			Bmask bmask{};
			Bindex bindex{};
			bool isReady() const {
				return state == EntryState::DISPATCHED && src1.ready && src2.ready;
			}
			static Entry createFromDispatch(const DispatchInst& dispatchInst) {
				assert(dispatchInst.valid);
				Entry ret;
				ret.decInst = dispatchInst.decInst;
				ret.state = EntryState::DISPATCHED;
				auto& di = dispatchInst.decInst;
				ret.fuType = (di.isCondBr || di.isUncondBr) ? FuType::br : (
					di.isMult ? FuType::mul : (
						di.rdMem || di.wrMem ? FuType::mem : (
							di.isIllegal ? FuType::nop : (
								di.isHalt ? FuType::halt :FuType::alu
							)
						)
					)
				);
				ret.dst = dispatchInst.decInst.dst;
				ret.src1 = dispatchInst.decInst.src1;
				ret.src2 = dispatchInst.decInst.src2;
				ret.bmask = dispatchInst.bmask;
				ret.bindex = dispatchInst.bindex;
				return ret;
			}
			::std::string to_string() const {
				::std::stringstream ss;
				ss << "state: " << (state == EntryState::DISPATCHED ? "DISPATCHED" : "EMPTY") << ", fuType: ";
				switch (fuType) {
				case FuType::alu:
					ss << "ALU";
					break;
				case FuType::mul:
					ss << "MUL";
					break;
				case FuType::mem:
					ss << "MEM";
					break;
				case FuType::br:
					ss << "BR";
					break;
				case FuType::halt:
					ss << "HALT";
					break;
				default:
					ss << "NOP";
					break;
				}
				ss << "; " << "src1: " << src1.tag.to_ulong() << ", state: " << src1.ready;
				ss << ", src2: " << src2.tag.to_ulong() << ", state: " << src2.ready << "; dst: " << dst.to_ulong();
				return ss.str();
			}
		};

		class RS {
		public:
			std::array<Entry, NUM_RS_ENTRIES> entries{};
			// called at the beginning of each cycle to clear data from previous cycle
			void onCycleStart();
			void reset();
			// CDB Broadcast
			void onCdbBc(const std::array<Tag, N>& cdbTags);
			void onBrRes(const BrResPacket& brRes);
			std::array<Tag, NUM_FU> getReadyTags();
			// receive FU availabilities from issue register
			void recIssAvails(const FUAvailsPacket& availPack);
			// void recCdbArbiterGnts(const std::bitset<NUM_FU>& gnts);
			IssuePacket issue();
			uint32_t getFreeSpotNum() const;
			void recDispatch(const std::array<DispatchInst, N>& dispatchInsts/*, const std::array<Tag, N>& cdbTags*/);
			std::string streamRegister() const;
		private:
			enum class State {
				init,
				completed,
				issued,
				dispatched
			} state{};

			// entry_idx -> fu_idx
			std::unordered_map<uint32_t, uint32_t> aluIssued{}, mulIssued{}, memIssued{}, brIssued{}, haltIssued{};
		};
	}

	
}


