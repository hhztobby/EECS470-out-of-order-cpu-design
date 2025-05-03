#pragma once

#include <array>
#include <unordered_map>
#include <bit>
#include "register.h"
#include "instruction.h"
#include "common.h"

namespace cpu {
	class MT {
	public:
		MT() {
			reset();
		}
		void reset() {
			for (int i = 0; i < NUM_AR; i++) {
				tags[i] = { Tag(i) , 0 };
			}
			tags[0] = { 0, 1 };
			for (int i = 0; i < BRANCH_STACK_SIZE; i++) {
				copies[i] = tags;
			}
		}
		void recCDBTagMasks(
			const std::array<Tag, N>& tags,
			const std::array<Bmask, N>& bmasks) {
			auto updateTableWithTags = [&](std::array<TagPlus, NUM_AR>& table, Tag tag) {
				for (int i = 0; i < NUM_AR; i++) {
					if (table[i].tag == tag) {
						// assert(table[i].ready == 0);
						table[i].ready = 1;
					}
				}
				};
			for (int i = 0; i < N; i++) {
				if (tags[i] != 0) {
					updateTableWithTags(this->tags, tags[i]);
					for (uint32_t j = 0; j < BRANCH_STACK_SIZE; j++) {
						Bindex bindex{};
						bindex.data = (1ULL << j);
						if (!bmasks[i].hasSharedBit(bindex)) { // update not dependent ones
							updateTableWithTags(copies[j], tags[i]);
						}
					}
				}
			}
			
		}
		void onBrRes(const BrResPacket& brRes) {
			if (brRes.state == BrResState::mis) {
				tags = copies[std::countr_zero(brRes.bindex.data.to_ulong())];
			}
		}
		std::array<TagPlus, N * 3> getTagsForDispatcher(const std::array<RegIdx, N * 3>& regs, 
			const std::array<Tag, N>& newDstTags,
			const std::array<Bindex, N>& brIndices,
			std::bitset<N> isBranch) {
			std::array<TagPlus, N * 3> ret{};
			for (int i = 0; i < N; i++) {
				ret[i*3] = tags[regs[i * 3].to_ulong()];
				ret[i*3+1] = tags[regs[i * 3 + 1].to_ulong()];
				ret[i*3+2] = tags[regs[i * 3 + 2].to_ulong()]; // get old dst tag
				if (regs[i * 3 + 2] != 0) {
					tags[regs[i * 3 + 2].to_ulong()] = { newDstTags[i], 0 }; // update to new dst tag
				}
				if (isBranch[i]) {
					copies[std::countr_zero(brIndices[i].data.to_ulong())] = tags;
				}
			}
			return ret;
		}
		/*void recNewDstTags(const std::array<RegIdx, N>& dstRegs,
			const std::array<Tag, N>& newDstTags,
			const std::array<Bindex, N>& brIndices, 
			std::bitset<N> isBranch) {
			for (int i = 0; i < N; i++) {
				if (dstRegs[i] != 0) {
					if (isBranch[i]) {
						copies[std::countr_zero(brIndices[i].data.to_ulong())] = tags;
					}
					tags[dstRegs[i].to_ulong()] = { newDstTags[i], 0 };
				}
			}
		}*/
	private:
		std::array<TagPlus, NUM_AR> tags{};
		std::array<std::array<TagPlus, NUM_AR>, BRANCH_STACK_SIZE> copies {};
	};
}
