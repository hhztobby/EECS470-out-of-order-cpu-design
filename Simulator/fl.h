#pragma once

#include <set>
#include <array>
#include <cassert>
#include <bit>
#include "register.h"
#include "common.h"

namespace cpu {
	class FL {
	public:
		FL() {
			reset();
		}
		void reset() {
			for (int i = NUM_AR; i < NUM_PR; i++) {
				tags.insert(i);
			}
			for (int i = 0; i < BRANCH_STACK_SIZE; i++) {
				copies[i] = tags;
			}
			onCycleStart();
		}
		void onCycleStart() {
			availTags.fill(0);
		}
		void recOldTags(const std::array<Tag, N>& tags) {
			for (int i = 0; i < N; i++) {
				if (tags[i] != 0) {
					assert(this->tags.find(tags[i].to_ulong()) == this->tags.end());
					this->tags.insert(tags[i].to_ulong());
				}
			}
		}
		void onBrRes(const BrResPacket& brRes) {
			if (brRes.state == BrResState::mis) {
				tags = copies[std::countr_zero(brRes.bindex.data.to_ulong())];
			}
		}
		std::array<Tag, N> getAvailableTags() {
			std::array<Tag, N> ret{};
			for (int i = 0; i < N; i++) {
				if (tags.size() <= i) break;
				auto it = tags.begin();
				for (int j = 0; j < i; j++) {
					it++;
				}
				ret[i] = Tag(*it);
				availTags[i] = *it;
			}
			return ret;
		}

		void recTags(const std::array<Tag, N>& tags) {
			for (int i = 0; i < N; i++) {
				if (tags[i] != 0) {
					assert(this->tags.find(tags[i].to_ulong()) == this->tags.end());
					this->tags.insert(tags[i].to_ulong());
				}
			}
		}
		void recTakenTagBits(const std::bitset<N>& taken, 
			const std::array<Bindex, N>& brIndices,
			std::bitset<N> isBranch) {
			for (int i = 0; i < N; i++) {
				if (taken[i]) {
					tags.erase(availTags[i]);
					if (isBranch[i]) {
						copies[std::countr_zero(brIndices[i].data.to_ulong())] = tags;
					}
				}
			}
		}

	private:
		/*struct TagComparator {
			bool operator()(const Tag& a, const Tag& b) const {
				return a.to_ulong() < b.to_ulong();
			}
		};*/
		std::array<uint32_t, N> availTags{};
		std::set<uint32_t> tags{};
		std::array<std::set<uint32_t>, BRANCH_STACK_SIZE> copies{};
	};
}