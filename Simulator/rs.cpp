
#include "rs.h"
#include <cassert>
#include <bitset>
#include <vector>
#include <algorithm>
#include "unordered_map"
#include "utils.h"

// reservation station

using namespace cpu;
using namespace cpu::rs;

void RS::onCycleStart() {
	state = State::init;
	aluIssued.clear();
	mulIssued.clear();
	memIssued.clear();
	brIssued.clear();
	for (auto& entry : entries) {
		if (entry.state == EntryState::DISPATCHED) {
			entry.earlyTag1 = 0;
			entry.earlyTag2 = 0;
		}
	}
}

void RS::reset() {
	onCycleStart();
	for (auto& entry : entries) {
		entry = {};
	}
}

void RS::onCdbBc(const std::array<Tag, N>& cdbTags) {
	assert(state == State::init);
	for (auto& entry : entries) {
		if (entry.state == EntryState::DISPATCHED) {
			for (const auto tag : cdbTags) {
				if (tag == 0) continue;
				if (entry.src1.tag == tag) {
					assert(entry.src1.ready == 0);
					entry.src1.ready = 1;
					entry.earlyTag1 = 1;
				}
				if (entry.src2.tag == tag) {
					assert(entry.src2.ready == 0);
					entry.src2.ready = 1;
					entry.earlyTag2 = 1;
				}
			}
		}
	}
}

void RS::onBrRes(const BrResPacket& brRes) {
	assert(state == State::init);
	state = State::completed;
	// if misprediction, squash
	if (brRes.state == BrResState::mis) {
		for (auto& entry : entries) {
			if (entry.state == EntryState::DISPATCHED &&
				entry.bmask.hasSharedBit(brRes.bindex)) {
				entry.state = EntryState::EMPTY;
			}
		}
	} else if (brRes.state == BrResState::hit) {
		for (auto& entry : entries) {
			if (entry.state == EntryState::DISPATCHED &&
				entry.bmask.hasSharedBit(brRes.bindex)) {
				entry.bmask.clearBit(brRes.bindex);
			}
		}
	}
}

void RS::recIssAvails(const FUAvailsPacket& availPack) {
	assert(state == State::completed);
	auto issueFU = [this, &availPack](std::unordered_map<uint32_t, uint32_t>& reqs) {
		for (int i = 0; i < NUM_ALU; i++) {
			if (!availPack.avails[i]) {
				std::erase_if(reqs, [i](const auto& pair) { return pair.second == i; });
			}
		}
		};
	issueFU(aluIssued);
	issueFU(mulIssued);
	issueFU(memIssued);
	issueFU(brIssued);
}

std::array<Tag, NUM_FU> RS::getReadyTags() {
	assert(state == State::completed);
	std::array<Tag, NUM_FU> tags{};
	auto reqFU = [this, &tags] <uint32_t cnt>(FuType targetFU, uint32_t fuOffset, bool dontRequestTag = false) -> std::unordered_map<uint32_t, uint32_t> {
		std::unordered_map<uint32_t, uint32_t> ret;
		std::bitset<NUM_RS_ENTRIES> valid(0);
		for (int i = 0; i < NUM_RS_ENTRIES; i++) {
			if (entries[i].isReady() && entries[i].fuType == targetFU) {
				valid[i] = 1;
			}
		}
		// indices of selected entries
		auto issueSide = PSel_Alt<NUM_RS_ENTRIES, cnt>(valid).getGntInds();
		for (int i = 0; i < issueSide.size(); i++) {
			ret[issueSide[i]] = i + fuOffset;
			// everyone requests CDB!
			if (!dontRequestTag) tags[i + fuOffset] = entries[issueSide[i]].dst;
		}
		return ret;
		};
	aluIssued = reqFU.operator() <NUM_ALU> (FuType::alu, 0);
	mulIssued = reqFU.operator() <NUM_MUL> (FuType::mul, NUM_ALU, true); // mult doesn't request tag when issue
	memIssued = reqFU.operator() <NUM_MEM> (FuType::mem, NUM_ALU + NUM_MUL);
	brIssued = reqFU.operator() <NUM_BR> (FuType::br, NUM_ALU + NUM_MUL + NUM_MEM);
	haltIssued = reqFU.operator() <NUM_HALT> (FuType::halt, NUM_ALU + NUM_MUL + NUM_MEM + NUM_BR);
	return tags;
}
/*
void RS::recCdbArbiterGnts(const std::bitset<NUM_FU>& gnts) {
	assert(state == State::completed);
	for (int i = 0; i < NUM_ALU; i++) {
		if (!gnts[i]) {
			aluIssued.erase(i);
		}
	}
}
*/

IssuePacket cpu::rs::RS::issue() {
	IssuePacket ret;
	assert(state == State::completed);
	state = State::issued;
	auto issueFu = [this, &ret](const std::unordered_map<uint32_t, uint32_t>& fuIssued) -> void {
		for (const auto& [entry_idx, fu_idx] : fuIssued) {
			entries[entry_idx].state = EntryState::EMPTY;
			ret.insts[fu_idx].valid = 1;
			ret.insts[fu_idx].inst = entries[entry_idx].decInst;
			ret.insts[fu_idx].bmask = entries[entry_idx].bmask;
			ret.insts[fu_idx].bindex = entries[entry_idx].bindex;
			ret.insts[fu_idx].earlyTag1 = entries[entry_idx].earlyTag1;
			ret.insts[fu_idx].earlyTag2 = entries[entry_idx].earlyTag2;
			if constexpr (LOG::rs) {
				LOG::log(LOG::LogLevel::simple, std::format("[rs]: Issued instruction from entry {}, with fu idx {} ", entry_idx, fu_idx));
				LOG::log(LOG::LogLevel::verbose, std::format("[rs]: details: bmask = {};\
				 src1 = {}, src2 = {}, dst tag = {}, dst reg = {};\
					src1 affected by etb = {}, src2 = {}", ret.insts[fu_idx].bmask.data.to_string(),
					ret.insts[fu_idx].inst.src1.tag.to_ulong(), ret.insts[fu_idx].inst.src2.tag.to_ulong(),
					ret.insts[fu_idx].inst.dst.to_ulong(), ret.insts[fu_idx].inst.dstRegIdx.to_ulong(),
					ret.insts[fu_idx].earlyTag1, ret.insts[fu_idx].earlyTag2));
			}
		}
	};
	issueFu(aluIssued);
	issueFu(mulIssued);
	issueFu(memIssued);
	issueFu(brIssued);
	issueFu(haltIssued);
	return ret;
}

uint32_t RS::getFreeSpotNum() const {
	assert(state == State::issued);
	uint32_t ret = 0;
	for (const auto& entry : entries) {
		if (entry.state == EntryState::EMPTY) {
			ret++;
		}
	}
	return ret;
}

void RS::recDispatch(const std::array<DispatchInst, N>& dispatchInsts/*, const std::array<Tag, N>& cdbTags*/) {
	assert(state == State::issued);
	state = State::dispatched;
	std::bitset<N> dispatchValidities(0);
	std::bitset<NUM_RS_ENTRIES> entryReadyBits(0);
	for (int i = 0; i < N; i++) {
		if (dispatchInsts[i].valid) {
			dispatchValidities[i] = 1;
		}
	}
	for (int i = 0; i < NUM_RS_ENTRIES; i++) {
		if (entries[i].state == EntryState::EMPTY) {
			entryReadyBits[i] = 1;
		}
	}
	auto dispatchSide = PSel_Alt<N, N>(dispatchValidities).getGntInds();
	auto entrySide = PSel_Alt<NUM_RS_ENTRIES, N>(entryReadyBits).getGntInds();
	for (int i = 0; i < dispatchSide.size() && i < entrySide.size(); i++) {
		auto newEntry = Entry::createFromDispatch(dispatchInsts[dispatchSide[i]]);
		if constexpr (LOG::rs) {
			LOG::log(LOG::LogLevel::simple, std::format("[rs]: Dispatch an instruction to entry {}", entrySide[i]));
		}
		/*for (const auto tag : cdbTags) {
			if (newEntry.src1.tag == tag) {
				newEntry.src1.ready = 1;
			}
			if (newEntry.src2.tag == tag) {
				newEntry.src2.ready = 1;
			}
		}*/
		if (newEntry.src1.tag == 0) {
			newEntry.src1.ready = 1;
		}
		if (newEntry.src2.tag == 0) {
			newEntry.src2.ready = 1;
		}
		if constexpr (LOG::rs) {
			LOG::log(LOG::LogLevel::verbose, std::format("[rs]: Instruction src: 1 - {}, ready = {}; 2 - {}, ready = {}", 
				newEntry.src1.tag.to_ulong(), newEntry.src1.ready, 
				newEntry.src2.tag.to_ulong(), newEntry.src2.ready));
		}
		entries[entrySide[i]] = std::move(newEntry);
	}
	if constexpr (LOG::rs) {
		for (int i = 0; i < NUM_RS_ENTRIES; i++) {
			LOG::log(LOG::LogLevel::verbose, std::format("[rs]: Entry[{}]: {}", i, entries[i].to_string()));
		}
	}

}

std::string cpu::rs::RS::streamRegister() const
{
	std::stringstream ss{};
	ss << "[rs registers]" << std::endl;
	for (int i = 0; i < NUM_RS_ENTRIES; i++) {
		ss << entries[i].to_string() << std::endl;
	}
	return ss.str();
}

