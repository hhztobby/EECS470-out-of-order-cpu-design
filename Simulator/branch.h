#pragma once

#include "common.h"
#include <cassert>
#include <bitset>

namespace cpu {

	struct Bindex {
		std::bitset<BRANCH_STACK_SIZE> data{};
		bool operator==(const Bindex& other) const {
			return data == other.data;
		}
		bool isValid() const {
			return data.count() == 1;
		}
	};

	struct Bmask {
		std::bitset<BRANCH_STACK_SIZE> data{};
		bool hasSharedBit(const Bindex& other) const {
			assert(other.isValid());
			return (data & other.data).any();
		}
		void clearBit(const Bindex& other) {
			assert(other.isValid());
			data &= ~other.data;
		}
	};

	enum class BrResState {
		empty,
		hit,
		mis
	};

	struct BrResPacket {
		BrResState state{};
		Bindex bindex{};
	};

	struct BranchStackEntry {
		bool occupied = 0;
		Bmask bmask{};
		Bindex bindex{};
	};

	class BranchStack {
	public:
		void reset() {
			availSpots = BRANCH_STACK_SIZE;
			for (auto& entry : entries) {
				entry.occupied = 0;
				entry.bmask.data.reset();
				entry.bindex.data.reset();
			}
		}
		uint32_t getSpotsNum() const {
			return availSpots;
		}
		std::bitset<BRANCH_STACK_SIZE> getEmptyEntryBits() const {
			std::bitset<BRANCH_STACK_SIZE> ret;
			for (int i = 0; i < BRANCH_STACK_SIZE; i++) {
				if (!entries[i].occupied) {
					ret.set(i);
				}
			}
			return ret;
		}
		void onBrRes(const BrResPacket& packet) {
			if (packet.state == BrResState::mis) {
				for (auto& entry : entries) {
					if (entry.occupied && (entry.bmask.hasSharedBit(packet.bindex) || entry.bindex == packet.bindex)) {
						entry.occupied = 0;
						availSpots++;
					}
				}
			}
			else if (packet.state == BrResState::hit) {
				for (auto& entry : entries) {
					if (entry.occupied) {
						entry.bmask.clearBit(packet.bindex);
					}
					if (entry.bindex == packet.bindex) {
						entry.occupied = 0;
						availSpots++;
					}
				}
			}
		}
		Bmask getCurrentBmask() const {
			Bmask bmask = {};
			for (int i = 0; i < BRANCH_STACK_SIZE; i++) {
				if (entries[i].occupied) {
					bmask.data |= entries[i].bindex.data;
				}
			}
			return bmask;
		}
		BranchStackEntry allocateEntry() {
			assert(availSpots > 0);
			for (uint32_t i = 0; i < BRANCH_STACK_SIZE; i++) {
				if (!entries[i].occupied) {
					return allocateEntryIndexed(i);
				}
			}
			return {};
		}
		BranchStackEntry allocateEntryIndexed(uint32_t idx) {
			assert(availSpots > 0);
			assert(idx < BRANCH_STACK_SIZE);
			assert(!entries[idx].occupied);
			// do not contain its own bindex
			// logic: an instruction should not invalidate itself!
			entries[idx].bmask = getCurrentBmask();
			entries[idx].occupied = 1;
			entries[idx].bindex.data = (1ULL << idx);
			availSpots--;
			return entries[idx];
		}
	private:
		std::array<BranchStackEntry, BRANCH_STACK_SIZE> entries{};
		uint32_t availSpots = BRANCH_STACK_SIZE;
	};
}

