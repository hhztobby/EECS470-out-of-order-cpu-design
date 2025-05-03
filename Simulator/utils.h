#pragma once
#include <bitset>
#include <vector>

namespace cpu {
	// alternates between MSB and LSB
	template <uint32_t WIDTH, uint32_t REQS>
	class PSel_Alt {
	public:
		PSel_Alt(const std::bitset<WIDTH> reqs) {
			int cnt = 0;
			for (int left = 0, right = WIDTH - 1; left <= right && cnt < REQS; ) {
				while (left <= right && reqs[right] == 0) {
					right--;
				}
				if (right < left) {
					break;
				}
				gnt[right] = 1;
				cnt++;
				gntInds.push_back(right--);
				if (cnt == REQS) {
					break;
				}
				while (left <= right && reqs[left] == 0) {
					left++;
				}
				if (right < left) {
					break;
				}
				gnt[left] = 1;
				cnt++;
				gntInds.push_back(left++);
			}
		}
		std::bitset<WIDTH> getGnt() const {
			return gnt;
		}
		// indices of selected reqs
		std::vector<uint32_t> getGntInds() const {
			return gntInds;
		}
	private:
		std::vector<uint32_t> gntInds;
		std::bitset<WIDTH> gnt;
	};
};