#pragma once

#include "instruction.h"
#include "cdb.h"
#include <array>
#include <iostream>
#include <bit>
#include <sstream>

namespace cpu {
	namespace rob {

		inline constexpr uint32_t ROB_SIZE = NUM_PR + 1;

		struct RobEntry {
			bool isValidEntry = 0;
			RegIdx dst{};
			Tag dstTagNew{};
			Tag dstTagOld{};
			pc_t npc{};
			Data data{};
			bool isHalt = 0;
			bool isIllegal = 0;
			bool isValid = 0;
			bool completed = 0;
		};

		class ROB {
		public:
			static constexpr uint32_t retire_size = N;
			void reset() {
				entries.fill({});
				head = 0;
				tail = 0;
				freeSpots = ROB_SIZE;
				tailCopies.fill(0);
				freeSpotNumCopies.fill(ROB_SIZE);
				onCycleStart();
				haltRetired = false;
			}
			void onCycleStart() {
				retiredOldTags.fill(0);
			}
			void retire(const std::vector<Inst>& instBuffer) {
				for (int i = 0; i < retire_size && head != tail; i++) {
					if (entries[head].completed) {
						if constexpr (LOG::rob) {
							unsigned long value = entries[head].data.to_ulong();
							std::stringstream ss;
							ss << std::hex << value;
							LOG::getInstance().logWb(entries[head].npc.to_ulong() - 4, 
								instBuffer[entries[head].npc.to_ulong()/4-1].data.to_ulong(),
								entries[head].dst.to_ulong(), entries[head].data.to_ulong());
							LOG::log(LOG::LogLevel::simple, std::format(
								"Instruction retired: npc/4 = {}, data = {}, reg_idx = {}, isHalt = {}, isIllegal = {}", 
								entries[head].npc.to_ulong() / 4, ss.str(),
								entries[head].dst.to_ulong(), entries[head].isHalt, entries[head].isIllegal
							));
							LOG::log(LOG::LogLevel::simple, std::format(
								"new tag = {}, old tag = {}",
								entries[head].dstTagNew.to_ulong(), entries[head].dstTagOld.to_ulong()
							));
						}
						retiredOldTags[i] = entries[head].dstTagOld;
						freeSpots++;
						if (entries[head].isHalt) {
							haltRetired = true;
						}
						head = (head + 1) % ROB_SIZE;
					}
					else {
						break;
					}
				}
			}
			bool shouldStop() const {
				return haltRetired;;
			}
			std::array<Tag, retire_size> getRetiredOldTags() const {
				return retiredOldTags;
			}
			void recCDBData(const std::array<CDBLine, N>& cdbLines) {
				for (int i = 0; i < N; i++) {
					if (cdbLines[i].tag != 0) {
						for (int j = head; j != tail; j = (j + 1) % ROB_SIZE) {
							if (entries[j].dstTagNew == cdbLines[i].tag) {
								assert(entries[j].completed == 0);
								entries[j].data = cdbLines[i].data;
								entries[j].completed = 1;
								if constexpr (LOG::rob) {
									LOG::log(LOG::LogLevel::verbose, std::format(
										"[cdb] Rob entry [{}] completed: npc/4 = {}, reg_idx = {}, tag new = {}, tag old = {}", 
										j, entries[j].npc.to_ulong() / 4, 
										entries[j].dst.to_ulong(), entries[j].dstTagNew.to_ulong(), entries[j].dstTagOld.to_ulong()
									));
								}
								break;
							}
						}
					}
				}
			}
			void onBrRes(const BrResPacket& packet) {
				if (packet.state == BrResState::mis) {
					tail = tailCopies[std::countr_zero(packet.bindex.data.to_ulong())];
					freeSpots = freeSpotNumCopies[std::countr_zero(packet.bindex.data.to_ulong())];
				}
			}
			uint32_t getFreeSpotNum() const {
				return freeSpots;
			}
			void recDispatchEntries(const std::array<RobEntry, N>& newEntries,
				const std::array<Bindex, N>& brIndices,
				std::bitset<N> isBranch) {
				for (int i = 0; i < N; i++) {
					if (!newEntries[i].isValidEntry) break;
					assert(freeSpots > 0);
					entries[tail] = newEntries[i];
					tail = (tail + 1) % ROB_SIZE;
					freeSpots--;
					if (isBranch[i]) {
						tailCopies[std::countr_zero(brIndices[i].data.to_ulong())] = tail;
						freeSpotNumCopies[std::countr_zero(brIndices[i].data.to_ulong())] = freeSpots;
					}
				}
			}
		private:
			std::array<RobEntry, ROB_SIZE> entries{};
			// tail is next available entry
			uint32_t head = 0, tail = 0, freeSpots = ROB_SIZE;
			std::array<uint32_t, BRANCH_STACK_SIZE> tailCopies{};
			std::array<uint32_t, BRANCH_STACK_SIZE> freeSpotNumCopies{};
			std::array<Tag, retire_size> retiredOldTags{};
			bool haltRetired = false;
		};
	}
}