#pragma once

#include <array>
#include <algorithm>
#include <ranges>
#include <format>
#include "register.h"
#include "common.h"
#include "branch.h"
#include "utils.h"
#include "instruction.h"

namespace cpu {

	struct CDBLine {
		Tag tag{};
		Data data{};
	};

	class CDB {
	public:
		void reset() {
			earlyTagReg.fill(0);
			cdbLines.fill({ 0, 0 });
			cdbArbiterGnts.reset();
			brResPacket = {};
			notRequestedFus.reset();
			cdbBmasks.fill(Bmask());
			targetPC = 0;

			onCycleStart();
		}
		void onCycleStart() {
			// don't clear any register here!
		}
		BrResPacket getBrResPacket() const {
			return brResPacket;
		}
		pc_t getBrResPc() const {
			return brResPacket.bindex.isValid() ? targetPC : 0;
		}
		std::array<Tag, N> getEarlyCDBTags() const {
			return earlyTagReg;
		}
		//Do NOT use this to get tags! Tags in lines are just identifiers
		std::array<CDBLine, N> getCdbLines() const {
			return cdbLines;
		}
		std::array<Data, 2 * NUM_FU> getCdbData(const std::array<Tag, 2 * NUM_FU>& tags) const {
			std::array<Data, 2 * NUM_FU> ret{};
			for (int i = 0; i < 2 * NUM_FU; i++) {
				for (int j = 0; j < N; j++) {
					if (cdbLines[j].tag == tags[i]) {
						ret[i] = cdbLines[j].data;
					}
				}
			}
			return ret;
		}
		std::array<Bmask, N> getCdbBmasks() const {
			return cdbBmasks;
		}
		void recExRes(const std::array<CDBLine, NUM_FU>& lines, 
			const std::array<Bmask, NUM_FU>& bmasks,
			BrResPacket packet, pc_t targetPC
		) {
			assert(std::ranges::count_if(lines, [](const CDBLine& line) {return line.tag != 0;}) <= N);
			cdbLines.fill({ 0, 0 });
			int lineIdx = 0;
			for (int i = 0; i < NUM_FU; i++) {
				if (lines[i].tag != 0) {
					assert(cdbArbiterGnts[i]);
					if constexpr (LOG::cdb) {
						LOG::log(LOG::LogLevel::simple, std::format("[cdb]: Received ex result: tag = {}, data = {}", lines[i].tag.to_ulong(), lines[i].data.to_ulong()));
					}
					cdbLines[lineIdx] = lines[i];
					cdbBmasks[lineIdx] = bmasks[i];
					if (packet.state == BrResState::mis) {
						if (bmasks[i].hasSharedBit(packet.bindex)) {
							cdbLines[lineIdx] = { 0, 0 };
							if constexpr (LOG::cdb) {
								LOG::log(LOG::LogLevel::simple, std::format("[cdb]: However, the result is squashed due to branch misprediction"));
							}
						}
					}
					lineIdx++;
				}
			}
			brResPacket = packet;
			if (packet.state == BrResState::mis) {
				if constexpr (LOG::cdb) {
					LOG::log(LOG::LogLevel::simple, std::format("[cdb]: Received branch misprediction: set target pc = {}", targetPC.to_ulong()));
				}
				this->targetPC = targetPC;
			}
			else {
				this->targetPC = 0;
			}
		}
		pc_t getTargetPC() const {
			return targetPC;
		}
		void recCdbArbiterReqs(const std::array<Tag, NUM_FU>& dstTagsFromIssue,
			const std::array<Tag, NUM_FU>& dstTagsFromEX) {
			std::bitset<NUM_FU> reqsFromIssue(0), reqsFromEX(0);
			notRequestedFus.reset();
			cdbArbiterGnts.reset();
			earlyTagReg.fill(0);
			for (int i = 0; i < NUM_FU; i++) {
				if (dstTagsFromIssue[i] != 0) {
					reqsFromIssue[i] = 1;
				}
				if (dstTagsFromEX[i] != 0) {
					reqsFromEX[i] = 1;
				}
				if (dstTagsFromIssue[i] == 0 && dstTagsFromEX[i] == 0) {
					notRequestedFus[i] = 1;
				}
			}
			assert((reqsFromIssue & reqsFromEX) == 0);
			auto reqs = reqsFromIssue | reqsFromEX;
			if (reqs[NUM_ALU + NUM_MUL + NUM_MEM] == 1) { // branch requested
				cdbArbiterGnts[NUM_ALU + NUM_MUL + NUM_MEM] = 1;
				reqs[NUM_ALU + NUM_MUL + NUM_MEM] = 0;
				auto gnts = PSel_Alt<NUM_FU, N-1>(reqs).getGnt();
				cdbArbiterGnts |= gnts;
			}
			else {
				auto gnts = PSel_Alt<NUM_FU, N>(reqs).getGnt();
				cdbArbiterGnts |= gnts;
			}
			int earlyTagIdx = 0;
			for (int i = 0; i < NUM_FU; i++) {
				if (cdbArbiterGnts[i]) {
					assert(earlyTagIdx < N);
					assert(reqsFromIssue[i] == 0 || reqsFromEX[i] == 0);
					if (reqsFromIssue[i]) {
						earlyTagReg[earlyTagIdx++] = dstTagsFromIssue[i];
					}
					else if (reqsFromEX[i]) {
						earlyTagReg[earlyTagIdx++] = dstTagsFromEX[i];
					}
				}
			}
			if constexpr (LOG::cdb) {
				LOG::log(LOG::LogLevel::verbose, std::format("[cdb]: CDB arbiter reqs: {}", reqs.to_string()));
				LOG::log(LOG::LogLevel::simple, std::format("[cdb]: CDB arbiter gnts: {}", cdbArbiterGnts.to_string()));
				LOG::log(LOG::LogLevel::verbose, std::format("[cdb]: Next cycle, CDB will broadcast early tags: {}, {}", earlyTagReg[0].to_ulong(), earlyTagReg[1].to_ulong()));
			}
		}
		std::bitset<NUM_FU> getCdbArbiterGnts() const {
			return cdbArbiterGnts;
		}
		/*std::bitset<NUM_FU> getNotRequestedFus() const {
			return notRequestedFus;
		}*/ // currently we let everyone request cdb
	private:
		// cdb arbiter
		std::array<Tag, N> earlyTagReg{};
		// cdb register
		std::array<CDBLine, N> cdbLines{};
		std::array<Bmask, N> cdbBmasks{};
		std::bitset<NUM_FU> cdbArbiterGnts{};
		std::bitset<NUM_FU> notRequestedFus{};
		// branch result
		BrResPacket brResPacket{};
		pc_t targetPC{ 0 };
	};
}