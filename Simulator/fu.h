#pragma once

#include <bitset>
#include <array>
#include <string>
#include <sstream>
#include "branch.h"
#include "instruction.h"
#include "cdb.h"

namespace cpu {

	namespace {
		class ALU {
        public:
            Data execute(Data a, Data b, AluFunc func) {
                switch (func) {
                case AluFunc::add:
                    return Data(static_cast<uint32_t>(a.to_ulong() + b.to_ulong()));
                case AluFunc::sub:
                    return Data(static_cast<uint32_t>(a.to_ulong() - b.to_ulong()));
                case AluFunc::slt:
                    return Data(static_cast<uint32_t>(
                        static_cast<int32_t>(static_cast<uint32_t>(a.to_ulong())) <
                        static_cast<int32_t>(static_cast<uint32_t>(b.to_ulong()))));
                case AluFunc::sltu:
                    return Data(static_cast<uint32_t>(a.to_ulong() < b.to_ulong()));
                case AluFunc::and_:
                    return Data(a.to_ulong() & b.to_ulong());
                case AluFunc::or_:
                    return Data(a.to_ulong() | b.to_ulong());
                case AluFunc::xor_:
                    return Data(a.to_ulong() ^ b.to_ulong());
                case AluFunc::sll:
                    return Data(static_cast<uint32_t>(a.to_ulong() << (b.to_ulong() & 0b11111)));
                case AluFunc::srl:
                    return Data(static_cast<uint32_t>(a.to_ulong() >> (b.to_ulong() & 0b11111)));
                case AluFunc::sra:
                    return Data(static_cast<uint32_t>(
                        static_cast<int32_t>(static_cast<uint32_t>(a.to_ulong())) >>
                        (b.to_ulong() & 0b11111)));
                default:
                    assert(0);
                }
				return Data(0);
            }
		};

		enum class MultFunc {
			mul = 0,
			mulh = 1,
			mulhsu = 2,
			mulhu = 3
		};

        template<uint32_t NUM_STAGES>
			requires (NUM_STAGES >= 1)
        class MUL {
        public:
            void reset() {
                entries = {};
            }
			void onBrRes(const BrResPacket& packet) {
				for (int i = 0; i < NUM_STAGES; i++) {
                    if (packet.state == BrResState::mis) {
                        if (entries[i].valid && entries[i].bmask.hasSharedBit(packet.bindex)) {
                            entries[i].valid = false;
                        }
					}
                    else if (packet.state == BrResState::hit) {
                        if (entries[i].valid) {
                            entries[i].bmask.clearBit(packet.bindex);
                        }
                    }
				}
			}
			Data execute(/*bool granted, */Bmask& outBmask, Tag& outDstTag) {
                Data ret(0);
                if (entries[NUM_STAGES - 1].valid) {
                    auto func = entries[NUM_STAGES - 1].func;
                    auto a = entries[NUM_STAGES - 1].a;
                    auto b = entries[NUM_STAGES - 1].b;
                    uint32_t a_u = static_cast<uint32_t>(a.to_ulong());
                    uint32_t b_u = static_cast<uint32_t>(b.to_ulong());
                    int32_t a_s = static_cast<int32_t>(a_u);
                    int32_t b_s = static_cast<int32_t>(b_u);
                    switch (func) {
                    case MultFunc::mul: {
                        // Lower 32 bits of signed multiplication
                        int64_t product = static_cast<int64_t>(a_s) * static_cast<int64_t>(b_s);
                        ret = Data(static_cast<uint32_t>(product)); // Truncate to lower 32 bits
                        break;
                    }
                    case MultFunc::mulh: {
                        // Upper 32 bits of signed multiplication
                        int64_t product = static_cast<int64_t>(a_s) * static_cast<int64_t>(b_s);
                        ret = Data(static_cast<uint32_t>(product >> 32)); // Extract upper 32 bits
                        break;
                    }
                    case MultFunc::mulhu: {
                        // Upper 32 bits of unsigned multiplication
                        uint64_t product = static_cast<uint64_t>(a_u) * static_cast<uint64_t>(b_u);
                        ret = Data(static_cast<uint32_t>(product >> 32));
                        break;
                    }
                    case MultFunc::mulhsu: {
                        // Upper 32 bits of signed-unsigned multiplication
                        int64_t product = static_cast<int64_t>(a_s) * static_cast<uint64_t>(b_u);
                        ret = Data(static_cast<uint32_t>(product >> 32));
                        break;
                    }
                    default:
                        assert(0);
                    }
					outBmask = entries[NUM_STAGES - 1].bmask;
                    outDstTag = entries[NUM_STAGES - 1].dstTag;
                }
				entries[NUM_STAGES-1].valid = false;
                /*uint32_t start_move_pos = NUM_STAGES - 2;
                if (granted) {
                    assert (entries[NUM_STAGES-2].valid);
                    start_move_pos = NUM_STAGES - 1;
                }
                for (int i = start_move_pos; i >= 1; i--) {
                    if (!entries[i].valid) {
                        entries[i] = entries[i-1];
                        entries[i-1].valid = false;
                    }
                }*/
				return ret;
			}
			Tag getReadyTagNextCycle() const {
                if (entries[NUM_STAGES - 2].valid) {
                    return entries[NUM_STAGES - 2].dstTag;
                }
                return {};
			}
            void shiftStageData(bool granted) {
                uint32_t start_move_pos = MUL_STAGES - 2;
                if (granted) {
					start_move_pos = MUL_STAGES - 1;
                }
                for (int i = start_move_pos; i >= 1; i--) {
                    if (!entries[i].valid) {
                        entries[i] = entries[i - 1];
                        entries[i - 1].valid = false;
                    }
                }
            }
            void receive(Data a, Data b, uint32_t func, Tag dst, Bmask bmask) {
				assert(func < 4);
				assert(!entries[NUM_STAGES - 1].valid);
				entries[0] = { a, b, static_cast<MultFunc>(func), 1, dst, bmask };
            }
            bool availableNextCycle(bool granted) const {
                std::array<bool, NUM_STAGES> nextAvail{};
                nextAvail[NUM_STAGES - 1] = granted;
                for (int i = NUM_STAGES - 2; i >= 0; i--) {
                    nextAvail[i] = !entries[i].valid || nextAvail[i + 1];
                }
				return nextAvail[0];
            }
        struct MultEntry {
            Data a{};
            Data b{};
            MultFunc func{ MultFunc::mul };
            bool valid{ false };
            Tag dstTag{};
            Bmask bmask{};
            ::std::string to_string() {
                ::std::stringstream ss{};
                ss << "valid: " << valid << ", dstTag: " << dstTag.to_ulong() << ", bmask: " << bmask.data.to_string();
                return ss.str();
            }
        };
        std::array<MultEntry, NUM_STAGES> entries{};
        private:
        };
        class BranchUnit {
        public:
            bool execute_cond(Data a, Data b, uint32_t func, pc_t pc, Data imm, pc_t& outTargetPC) {
                assert(func < 7);

                uint32_t a_u = static_cast<uint32_t>(a.to_ulong());
                uint32_t b_u = static_cast<uint32_t>(b.to_ulong());
                int32_t a_s = static_cast<int32_t>(a_u);
                int32_t b_s = static_cast<int32_t>(b_u);

                bool take = 0;
                switch (func) {
                case 0: // BEQ
                    take = (a_s == b_s);
                    break;
                case 1: // BNE
                    take = (a_s != b_s);
                    break;
                case 4: // BLT
                    take = (a_s < b_s);
                    break;
                case 5: // BGE
                    take = (a_s >= b_s);
                    break;
                case 6: // BLTU
                    take = (a_u < b_u);
                    break;
                case 7: // BGEU
                    take = (a_u >= b_u);
                    break;
                default:
                    assert(0);
                }
				if (take) {
					outTargetPC = static_cast<uint32_t>(pc.to_ulong() + imm.to_ulong());
				}
				else {
					outTargetPC = 0;
				}
                return take;
            }

            Data execute_uncond(Data a, Data imm) {
                return static_cast<uint32_t>(a.to_ulong() + imm.to_ulong());
            }
        };
        
	};

	struct FUAvailsPacket {
		std::bitset<NUM_FU> avails;
	};
	class FU {
    public:
        void reset() {
			for (int i = 0; i < NUM_MUL; i++) {
				muls[i].reset();
			}
			onCycleStart();
        }
		void onCycleStart() {
			results.fill(Data(0));
			dsts.fill(0);
			brResPacket = {};
			targetPC = 0;
			bmasks.fill(Bmask());
			acceptedBits.reset();
		}
        void onBrRes(const BrResPacket& packet) {
			for (int i = 0; i < NUM_MUL; i++) {
				muls[i].onBrRes(packet);
			}
            for (int i = 0; i < NUM_FU; i++) {
                
                if (packet.state == BrResState::mis) {
                    if (bmasks[i].hasSharedBit(packet.bindex)) {
                        assert(0);
                    }
                }
                        /* // we expect this to be resolved elsewhere , e.g., issueReg
                        results[i] = {};
						dsts[i] = 0;
                        if constexpr (LOG::fu) {
                            LOG::log(LOG::LogLevel::simple, std::format("[fu]: Received branch misprediction: clear result of FU {}", i));
                        }
					}
                }
                else if (packet.state == BrResState::hit) {
                    if (bmasks[i].hasSharedBit(packet.bindex)) {
                        bmasks[i].clearBit(packet.bindex);
                    }
                }*/
            }
        }
        void execute(const std::array<ExInst, NUM_FU>& exInsts/*,
        std::bitset<NUM_FU> gnts*/) {
            for (int i = 0; i < NUM_ALU; i++) {
                if (exInsts[i].valid) {
                    acceptedBits[i] = 1;
                    Data a{}, b{};
                    switch (exInsts[i].opa) {
                        case AluOpASel::rs1:
                            a = exInsts[i].src1;
                            break;
					    case AluOpASel::pc:
						    a = exInsts[i].pc;
						    break;
					    case AluOpASel::npc:
						    a = exInsts[i].npc;
						    break;
					    case AluOpASel::zero:
						    a = Data(0);
						    break;
                        default:
						    assert(0);
                    }
                    switch (exInsts[i].opb) {
                        case AluOpBSel::rs2:
                            b = exInsts[i].src2;
                            break;
					    case AluOpBSel::iImm:
                            b = exInsts[i].inst.getIImm();
						    break;
					    case AluOpBSel::sImm:
						    b = exInsts[i].inst.getSImm();
						    break;
					    case AluOpBSel::bImm:
						    b = exInsts[i].inst.getBImm();
						    break;
					    case AluOpBSel::uImm:
						    b = exInsts[i].inst.getUImm();
						    break;
					    case AluOpBSel::jImm:
						    b = exInsts[i].inst.getJImm();
						    break;
					    default:
						    assert(0);
                    }
					results[i] = alu.execute(a, b, exInsts[i].aluFunc);
					bmasks[i] = exInsts[i].bmask;
					assert(exInsts[i].hasDst);
					dsts[i] = exInsts[i].dst;
                }
            }
            for (int i = NUM_ALU; i < NUM_ALU + NUM_MUL; i++) {
                results[i] = muls[i - NUM_ALU].execute(/*gnts[i], */bmasks[i], dsts[i]);
            }
            for (int i = NUM_ALU + NUM_MUL; i < NUM_ALU + NUM_MUL + NUM_MEM; i++) {
                if (exInsts[i].valid) {
                    assert(0);
                }
            }
			for (int i = NUM_ALU + NUM_MUL + NUM_MEM; i < NUM_ALU + NUM_MUL + NUM_MEM + NUM_BR; i++) {
				if (exInsts[i].valid) {
                    // assert(gnts[i]);
                    bool take = 0;
                    if (exInsts[i].isCondBr) {
						take = br.execute_cond(exInsts[i].src1, exInsts[i].src2, exInsts[i].inst.getFunct3(), exInsts[i].pc, exInsts[i].inst.getBImm(), targetPC);
                    }
                    else {
                        take = 1;
                        Data imm{};
						if (exInsts[i].inst.isJALR()) {
							imm = exInsts[i].inst.getIImm();
                            targetPC = (br.execute_uncond(exInsts[i].src1, imm).to_ulong() & ~0b1);
						}
						else if (exInsts[i].inst.isJAL()) {
							imm = exInsts[i].inst.getJImm();
                            targetPC = br.execute_uncond(exInsts[i].pc, imm);
                        }
                        else {
							assert(0);
                        }
                        results[i] = exInsts[i].npc;
                    }
                    brResPacket.bindex = exInsts[i].bindex;
                    brResPacket.state = (exInsts[i].predictedTaken == take) ?
                        BrResState::hit : BrResState::mis;
                    dsts[i] = exInsts[i].dst;
				}
			}
            for (int i = NUM_ALU + NUM_MUL + NUM_MEM + NUM_BR; i < NUM_FU; i++) {
                if (exInsts[i].valid) {
					// pass, simply pass dst to CDB
                    // assert (gnts[i]);
                    dsts[i] = exInsts[i].dst;
					acceptedBits[i] = 1;
                }
            }
        }
        std::bitset<NUM_FU> getAcceptedBits() const {
            return acceptedBits;
        }
		std::array<CDBLine, NUM_FU> getTagData() const {
			std::array<CDBLine, NUM_FU> ret{};
			for (int i = 0; i < NUM_FU; i++) {
				if (dsts[i] != 0) {
					ret[i] = CDBLine{ .tag = dsts[i], .data = results[i] };
				}
			}
			return ret;
		}
        std::array<Bmask, NUM_FU> getCompleteBmasks() const {
			return bmasks;
        }
        BrResPacket getBranchRes() const {
            return brResPacket;
        }
		pc_t getTargetPC() const {
			return brResPacket.state == BrResState::mis ? targetPC : 0;
		}
		std::array<Tag, NUM_FU> getReadyTags() const {
			std::array<Tag, NUM_FU> ret{};
			for (int i = NUM_ALU; i < NUM_ALU + NUM_MUL; i++) {
				ret[i] = muls[i - NUM_ALU].getReadyTagNextCycle();
			}
			return ret;
		}
        void recCdbArbiterGnts(const std::bitset<NUM_FU>& gnts/*,
            const std::bitset<NUM_FU>& notRequestedFus*/,
            const std::array<ExInst, NUM_FU>& exInsts) {
            readyForIssueNextCycle = {};
			for (int i = 0; i < NUM_ALU; i++) {
				if (gnts[i]) {
					readyForIssueNextCycle[i] = 1;
				}
			}
            for (int i = NUM_ALU; i < NUM_ALU + NUM_MUL; i++) {
                if constexpr (LOG::fu) {
                    LOG::log(LOG::LogLevel::verbose, std::format("[fu] After ex, mul unit [{}] status: ", i-NUM_ALU));
                    for (int j = 0; j < MUL_STAGES; j++) {
                        LOG::log(LOG::LogLevel::verbose, std::format("[fu] stage[{}]: {}", j, muls[i-NUM_ALU].entries[j].to_string()));
                    }
                }
				muls[i - NUM_ALU].shiftStageData(gnts[i]);
                if (!muls[i - NUM_ALU].entries[0].valid && exInsts[i].valid) {
					acceptedBits[i] = 1;
                    muls[i - NUM_ALU].receive(exInsts[i].src1, exInsts[i].src2, exInsts[i].inst.getFunct3(), exInsts[i].dst, exInsts[i].bmask);
                }
                readyForIssueNextCycle[i] = muls[i - NUM_ALU].availableNextCycle(gnts[i]);
            }
			for (int i = NUM_ALU + NUM_MUL; i < NUM_ALU + NUM_MUL + NUM_MEM; i++) {
                // dummy
				readyForIssueNextCycle[i] = gnts[i];
			}
            for (int i = NUM_ALU + NUM_MUL + NUM_MEM; i < NUM_FU; i++) {
                if (gnts[i]) {
                    readyForIssueNextCycle[i] = 1;
                }
            }
            if constexpr (LOG::fu) {
                LOG::log(LOG::LogLevel::simple, std::format("[fu] Next cycle, fu accept from issue availabilities: {}", readyForIssueNextCycle.to_string()));
            }
			/*for (i = 0; i < NUM_FU; i++) {
				if (notRequestedFus[i]) {
					readyForIssueNextCycle[i] = 1;
				}
			}*/
        }
        std::bitset<NUM_FU> getReadyForIssueNextCycle() const {
			return readyForIssueNextCycle;
        }
    private:
        ALU alu{};
		std::array<MUL<MUL_STAGES>, NUM_MUL> muls{};
		BranchUnit br{};
        std::array<Data, NUM_FU> results{};
        std::array<Tag, NUM_FU> dsts{};
        std::array<Bmask, NUM_FU> bmasks{};
		BrResPacket brResPacket{};
        std::bitset<NUM_FU> readyForIssueNextCycle{};
		pc_t targetPC{ 0 };
		std::bitset<NUM_FU> acceptedBits{ 0 };
	};
}