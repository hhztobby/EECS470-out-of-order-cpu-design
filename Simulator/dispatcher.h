#pragma once

#include <vector>

#include "instruction.h"
#include "common.h"
#include "decoder.h"
#include "branch.h"
#include "rob.h"
#include <unordered_map>

namespace cpu {

	class Dispatcher {
	public:
		void onCycleStart();
		void reset();
		void onBrRes(const BrResPacket& packet);
		void recTagsFromFL(const std::array<Tag, N>& tags);
		void recRSSpots(uint32_t num);
		void recRobSpots(uint32_t num);
		// uint32_t getFreeSpotsNum() const;
		// set dispatched insts, except srcs
		void recFetchInsts(const std::array<FetchInst, N>& fInsts);
		std::array<RegIdx, N* (2 + 1)> getInstRegs() const;
		void recDispatchTags(const std::array<TagPlus, N* (2 + 1)>& tagsFromMT);
		std::array<RegIdx, N> getDstRegs() const;
		std::array<Tag, N> getNewDstTags() const;
		// std::array<DispatchInst, N> getDispatchedInsts() const;
		std::bitset<N> getAccepted() const;
		std::bitset<N> getDispatched() const;
		std::bitset<N> getTakenTagBitsFL() const;
		
		std::array<DispatchInst, N> dispatch() const;
		std::array<Bindex, N> getDispatchedBranchIndices() const;
		std::bitset<N> getDispatchedIsBranch() const;
		std::array<rob::RobEntry, N> getRobEntries() const;

	private:
		BranchStack branchStack{};
		std::bitset<N> dispatchedIsBranch{};
		std::array<Bindex, N> dispatchBranchIndices{};

		std::array<Tag, N> tagsFromFL{};
		uint32_t freeRobSpotsNum = 0, freeRSSpotsNum = 0;

		BrResState brResState = BrResState::empty;

		std::bitset<N> acceptedFromFetch{};
		std::array<DispatchInst, N> dispatchInsts{};
		std::array<Tag, N> tagsOld{};
		std::bitset<N> takenTagBitsFL{};
		std::array<RegIdx, N> dstRegs{};
		std::array<Tag, N> newDstTags{};

		// for checking usage
		mutable bool dispatched = false;
	};
	
}