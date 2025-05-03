#pragma once

#include <unordered_map>
#include <array>
#include "instruction.h"
#include "common.h"
#include "cdb.h"

namespace cpu {
	class RegFile {
	public:
		void reset() {
			regs.clear();
		}
		void recCDBData(const std::array<CDBLine, N>& tagData) {
			for (const auto& [tag, value] : tagData) {
				if (tag != 0) regs[tag] = value;
			}
		}
		Data getData(Tag tag) const {
			if (tag == 0) return Data(0);
			auto it = regs.find(tag);
			// assert(it != regs.end());
			if (it != regs.end()) {
				return it->second;
			}
			return Data(UINT32_MAX);
		}
		std::array<Data, 2 * NUM_FU> readIssueData(const std::array<Tag, 2 * NUM_FU>& tags) const {
			std::array<Data, 2 * NUM_FU> ret{};
			for (int i = 0; i < 2 * NUM_FU; i++) {
				ret[i] = getData(tags[i]);
			}
			return ret;
		}
	private:
		std::unordered_map<Tag, Data> regs{};
	};
}
