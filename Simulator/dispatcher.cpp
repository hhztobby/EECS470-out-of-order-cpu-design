#include "dispatcher.h"
#include "decoder.h"
#include "utils.h"

#include <algorithm>
#include <ranges>
#include <sstream>

using namespace cpu;

void Dispatcher::onCycleStart() {
	dispatched = false;

	tagsFromFL = {};
	freeRobSpotsNum = UINT32_MAX;
	freeRSSpotsNum = UINT32_MAX;

	brResState = BrResState::empty;

	acceptedFromFetch = {};
	dispatchInsts = {};
	tagsOld = {};
	takenTagBitsFL = {};
	dstRegs = {};
	newDstTags = {};

	dispatchBranchIndices = {};
	dispatchedIsBranch = {};
}

void Dispatcher::reset() {
	branchStack.reset();
	onCycleStart();
}

void Dispatcher::onBrRes(const BrResPacket& packet) {
	branchStack.onBrRes(packet);
	brResState = packet.state;
}

void cpu::Dispatcher::recTagsFromFL(const std::array<Tag, N>& tags)
{
	tagsFromFL = tags;
}

void Dispatcher::recRobSpots(uint32_t num) {
	freeRobSpotsNum = num;
}

void Dispatcher::recRSSpots(uint32_t num) {
	freeRSSpotsNum = num;
}

/*uint32_t Dispatcher::getFreeSpotsNum() const {
	assert(freeRobSpotsNum != UINT32_MAX && freeRSSpotsNum != UINT32_MAX);
	uint32_t flSpotsNum = static_cast<uint32_t>(std::ranges::count_if(tagsFromFL, [](const Tag& tag) { return tag != 0; }));
	return std::min({ flSpotsNum, freeRobSpotsNum, freeRSSpotsNum, branchStack.getSpotsNum() });
}*/

void Dispatcher::recFetchInsts(const std::array<FetchInst, N>& fInsts) {
	if (brResState == BrResState::mis) {
		return;
	}
	auto availBrStackEntries = PSel_Alt<BRANCH_STACK_SIZE, N>(branchStack.getEmptyEntryBits()).getGntInds();
	int brEntryIdx = 0;
	std::bitset<N> availFLTagBits(0);
	for (int i = 0; i < N; i++) {
		if (tagsFromFL[i] != 0) {
			availFLTagBits[i] = 1;
		}
	}
	uint32_t flSpotsNum = static_cast<uint32_t>(std::ranges::count_if(tagsFromFL, [](const Tag& tag) { return tag != 0; }));
	for (uint32_t i = 0; i < N; i++) {
		const auto& finst = fInsts[i];
		if (!(finst.valid && freeRobSpotsNum > 0 && freeRSSpotsNum > 0 && i < flSpotsNum)) {
			if constexpr (LOG::dispatch) {
				LOG::log(LOG::LogLevel::verbose, std::format("[dispatch]: Inst {} not accepted due to structural hazard.", i));
			}
			break;
		}
		DecoderOut dout = decode(finst.inst);
		// assert(!dout.isIllegal); // we don't know how to deal with illegal for now
		if (dout.isIllegal) continue;
		DispatchInst dinst{};
		if (dout.condBr || dout.uncondBr) {
			if (brEntryIdx == availBrStackEntries.size()) {
				if constexpr (LOG::dispatch) {
					LOG::log(LOG::LogLevel::simple, std::format("[dispatch]: Inst {} is a branch, and it's not accepted due to branch stack structural hazard.", i));
				}
				break;
			}
			else {
				auto entry = branchStack.allocateEntryIndexed(availBrStackEntries[brEntryIdx++]);
				assert(entry.occupied);
				dinst.bindex = entry.bindex;
				dinst.bmask = entry.bmask;
				dispatchBranchIndices[i] = entry.bindex;
				dispatchedIsBranch[i] = 1;
				if constexpr (LOG::dispatch) {
					LOG::log(LOG::LogLevel::verbose, std::format("[dispatch]: Inst {} is a branch, allocated with bindex {}", i, entry.bindex.data.to_string()));
				}
			}
		}
		else {
			dinst.bmask = branchStack.getCurrentBmask();
		}
		dinst.valid = 1;
		dinst.predictedTaken = finst.predictedTaken;
		dinst.decInst = DecodedInst{
			.inst = finst.inst,
			.pc = finst.pc,
			.npc = finst.npc,
			/*
			* srcs assigned later,
			* see recDispatchTags
			*/
			.dst = tagsFromFL[i],
			.dstRegIdx = dout.hasDst ? finst.inst.getRd() : 0,
			.opa = dout.opa,
			.opb = dout.opb,
			.aluFunc = dout.aluFunc,
			.hasDst = dout.hasDst,
			.rdMem = dout.rdMem,
			.wrMem = dout.wrMem,
			.isMult = dout.isMult,
			.isCondBr = dout.condBr,
			.isUncondBr = dout.uncondBr,
			.isHalt = dout.isHalt,
			.isIllegal = dout.isIllegal
		};
		if constexpr (LOG::dispatch) {
			unsigned long value = finst.inst.data.to_ulong();
			std::stringstream ss;
			ss << std::hex << value;
			LOG::log(LOG::LogLevel::simple, std::format("[dispatch]: Dispatched instruction: inst = {}, pc/4 = {}", ss.str(), finst.pc.to_ulong() / 4));
		}
		takenTagBitsFL[i] = 1;
		dispatchInsts[i] = dinst;
		acceptedFromFetch[i] = 1;
		freeRobSpotsNum--;
		freeRSSpotsNum--;
		dstRegs[i] = dinst.decInst.dstRegIdx;
		newDstTags[i] = dinst.decInst.dst;
	}
	if constexpr (LOG::dispatch) {
		LOG::log(LOG::LogLevel::verbose, std::format("[dispatch]: Insts accepted status: {}", acceptedFromFetch.to_string()));
	}
	if constexpr (LOG::dispatch) {
		LOG::log(LOG::LogLevel::simple, std::format("[dispatch]: Insts dispatch status: 0 - {}, 1 - {}", dispatchInsts[0].valid, dispatchInsts[1].valid));
	}
}


void cpu::Dispatcher::recDispatchTags(const std::array<TagPlus, N* (2 + 1)>& tagsFromMT) {
	// assert(dispatched);
	for (int i = 0; i < N; i++) {
		if (!dispatchInsts[i].valid) break;
		dispatchInsts[i].decInst.src1 = tagsFromMT[i * 3 + 0];
		dispatchInsts[i].decInst.src2 = tagsFromMT[i * 3 + 1];
		tagsOld[i] = tagsFromMT[i * 3 + 2].tag;
	}
}

std::array<RegIdx, N> cpu::Dispatcher::getDstRegs() const
{
	return dstRegs;
}

std::array<Tag, N> cpu::Dispatcher::getNewDstTags() const
{
	return newDstTags;
}

std::bitset<N> cpu::Dispatcher::getAccepted() const {
	return acceptedFromFetch;
}

std::bitset<N> cpu::Dispatcher::getDispatched() const
{
	assert(dispatched);
	std::bitset<N> ret(0);
	for (int i = 0; i < N; i++) {
		if (dispatchInsts[i].valid) {
			ret[i] = 1;
		}
	}
	return ret;
}

std::bitset<N> cpu::Dispatcher::getTakenTagBitsFL() const
{
	return takenTagBitsFL;
}

std::array<RegIdx, N* (2 + 1)> cpu::Dispatcher::getInstRegs() const {
	std::array<RegIdx, N* (2 + 1)> ret{};
	for (int i = 0; i < N; i++) {
		if (!dispatchInsts[i].valid) break;
		const DecodedInst& dinst = dispatchInsts[i].decInst;
		const Inst& inst = dinst.inst;
		if (dinst.isCondBr) {
			ret[i * 3 + 0] = dinst.inst.getRs1();
			ret[i * 3 + 1] = dinst.inst.getRs2();
		}
		else if (dinst.isHalt) {
			// all src regs left 0
		}
		else {
			if (dinst.opa == AluOpASel::rs1) {
				ret[i * 3 + 0] = dinst.getRs1();
			}
			if (dinst.opb == AluOpBSel::rs2) {
				ret[i * 3 + 1] = dinst.getRs2();
			}
		}
		if (dinst.hasDst) {
			ret[i * 3 + 2] = dinst.getRd();
		}
	}
	return ret;
}

/*std::array<DispatchInst, N> cpu::Dispatcher::getDispatchedInsts() const
{
	assert(dispatched);
	return dispatchInsts;
}*/

std::array<DispatchInst, N> cpu::Dispatcher::dispatch() const {
	dispatched = true;
	return dispatchInsts;
}

std::array<Bindex, N> cpu::Dispatcher::getDispatchedBranchIndices() const {
	return dispatchBranchIndices;
}

std::bitset<N> cpu::Dispatcher::getDispatchedIsBranch() const
{
	return dispatchedIsBranch;
}

std::array<rob::RobEntry, N> cpu::Dispatcher::getRobEntries() const
{
	assert(dispatched);
	std::array<rob::RobEntry, N> ret{};
	for (int i = 0; i < N; i++) {
		if (!dispatchInsts[i].valid) break;
		auto& dinst = dispatchInsts[i];
		auto& decInst = dinst.decInst;
		ret[i] = rob::RobEntry{
			.isValidEntry = 1,
			.dst = decInst.dstRegIdx,
			.dstTagNew = decInst.dst,
			.dstTagOld = (decInst.hasDst && decInst.dstRegIdx != 0) ? tagsOld[i] : decInst.dst,
			.npc = decInst.npc,
			.isHalt = decInst.isHalt,
			.isIllegal = decInst.isIllegal,
			.isValid = 1
		};
	}
	return ret;
}
