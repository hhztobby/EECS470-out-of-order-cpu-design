#include <array>

#include "rs.h"
#include "issuereg.h"
#include "dispatcher.h"
#include "instruction.h"
#include "fetcher.h"
#include "cdb.h"
#include "regFile.h"
#include "fl.h"
#include "mt.h"
#include "rob.h"

// @TODO: ebr pc recovery: do we really need it?

void simulate() {
	constexpr int rounds = 2000;
	bool reset = 1;

	cpu::Fetcher fetcher{};
	cpu::Dispatcher dispatcher{};
	cpu::FL fl{};
	cpu::MT mt{};
	cpu::rs::RS rs{};
	cpu::IssueReg issueReg{};
	cpu::FU fu{};
	cpu::CDB cdb{};
	cpu::rob::ROB rob{};
	cpu::RegFile prf{};

	std::string path = "./programs/btest2.mem";

	fetcher.readIntoBuffer(path);


	for (int i = 0; i < rounds; i++) {
		LOG::log(LOG::LogLevel::simple, std::format("------------------------------ Start of round {} ------------------------------", i));
		LOG::getInstance().logRegister(std::format("cycle {}", i));
		if (reset) {
			fetcher.reset();
			dispatcher.reset();
			fl.reset();
			mt.reset();
			rs.reset();
			issueReg.reset();
			cdb.reset();
			rob.reset();
			prf.reset();
			reset = 0;
			continue;
		}
		fetcher.onCycleStart();
		dispatcher.onCycleStart();
		fl.onCycleStart();
		rs.onCycleStart();
		issueReg.onCycleStart();
		fu.onCycleStart();
		cdb.onCycleStart();
		rob.onCycleStart();

// retire
		rob.retire(fetcher.buffer);
		if (rob.shouldStop()) {
			return;
		}
		fl.recOldTags(rob.getRetiredOldTags());
// complete
		rs.onCdbBc(cdb.getEarlyCDBTags());
		rs.onBrRes(cdb.getBrResPacket());
		dispatcher.onBrRes(cdb.getBrResPacket());
		prf.recCDBData(cdb.getCdbLines());
		rob.recCDBData(cdb.getCdbLines());
		if (cdb.getBrResPacket().state == cpu::BrResState::mis) {
			fetcher.onBranchMispredict(cdb.getTargetPC());
		}
		rob.onBrRes(cdb.getBrResPacket());
		/* Early Branch Resolution: selective squash */
		issueReg.onBrRes(cdb.getBrResPacket());
		fu.onBrRes(cdb.getBrResPacket());
		/* Early Branch Resolution: update mt tag ready*/
		mt.recCDBTagMasks(cdb.getEarlyCDBTags(), cdb.getCdbBmasks());
		/* Early Branch Resolution: restore copies */
		mt.onBrRes(cdb.getBrResPacket());
		fl.onBrRes(cdb.getBrResPacket());

// execute
		fu.execute(issueReg.getExInsts()/*, cdb.getCdbArbiterGnts()*/);
		// cdb register updated
		cdb.recExRes(fu.getTagData(), fu.getCompleteBmasks(), fu.getBranchRes(), fu.getTargetPC());
// issue
		// cdb arbiter reg updated
		cdb.recCdbArbiterReqs(rs.getReadyTags(), fu.getReadyTags());
		fu.recCdbArbiterGnts(cdb.getCdbArbiterGnts()/*, cdb.getNotRequestedFus()*/, issueReg.getExInsts());
		issueReg.recFuAvails(fu.getReadyForIssueNextCycle(), fu.getAcceptedBits());
		rs.recIssAvails(issueReg.getIssAvails());
		// issue reg updated
		issueReg.recIssueInsts(rs.issue());
		issueReg.recData(cdb.getCdbData(issueReg.getIssSrcTags()), prf.readIssueData(issueReg.getIssSrcTags()));

// dispatch
		dispatcher.recTagsFromFL(fl.getAvailableTags());
		dispatcher.recRobSpots(rob.getFreeSpotNum());
		dispatcher.recRSSpots(rs.getFreeSpotNum());
		dispatcher.recFetchInsts(fetcher.getFetchedInsts());
		
		// maptable will output src tag_plus's and (old) dst tags, 
		// and update tag mappings
		dispatcher.recDispatchTags(
			mt.getTagsForDispatcher(dispatcher.getInstRegs(), dispatcher.getNewDstTags(), 
				dispatcher.getDispatchedBranchIndices(), dispatcher.getDispatchedIsBranch()));
		/*mt.recNewDstTags(dispatcher.getDstRegs(),
			);*/

		fetcher.recDispatcherAccepted(dispatcher.getAccepted());
		fl.recTakenTagBits(dispatcher.getTakenTagBitsFL(),
			dispatcher.getDispatchedBranchIndices(), dispatcher.getDispatchedIsBranch());
		rs.recDispatch(dispatcher.dispatch()/*, cdb.getEarlyCDBTags()*/); // don't need tags in sequential logic
		rob.recDispatchEntries(dispatcher.getRobEntries(),
			dispatcher.getDispatchedBranchIndices(), dispatcher.getDispatchedIsBranch());
		LOG::getInstance().logRegister<cpu::rs::RS>(rs);
		LOG::getInstance().logRegister({});
		LOG::log(LOG::LogLevel::simple, std::format("------------------------------ End of round {} ------------------------------\n", i));
	}

}

int main() {
	simulate();
	return 0;
}