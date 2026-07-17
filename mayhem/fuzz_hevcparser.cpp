// In-process libFuzzer harness for the HEVC elementary-stream parser.
//
// Drives exactly the same code path as the `hevcesbrowser_console` CLI target
// (HEVC::Parser::process over the raw file bytes), but in-process so the fuzzed
// parser code is instrumented and Mayhem collects edge coverage. The old
// file-input CLI target (`hevcesbrowser-console`) is preserved as this target's
// name; parity = the parser code path survives.
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

#include "Hevc.h"
#include "HevcParser.h"

using namespace HEVC;

namespace {
// Consumer that touches the produced NAL units so the parser's output is
// actually realized (not dead-code-eliminated) and more of the code path runs.
class FuzzConsumer : public Parser::Consumer {
 public:
  void onNALUnit(std::shared_ptr<NALUnit> pNALUnit,
                 const Parser::Info *pInfo) override {
    if (pNALUnit) {
      volatile NALUnitType t = pNALUnit->getType();
      (void)t;
    }
    (void)pInfo;
  }
  void onWarning(const std::string &warning, const Parser::Info *pInfo,
                 Parser::WarningType type) override {
    (void)warning;
    (void)pInfo;
    (void)type;
  }
};
}  // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  // Upstream OOB guard: HevcParserImpl::parse() trims trailing zero bytes with
  //   for (i=0;i<3;i++) if (pdata[size - i - 1] == 0) ...
  // which reads below the buffer (pdata[SIZE_MAX] for size==0) whenever size < 3.
  // libFuzzer always executes the empty input first, so without this guard the
  // target aborts at init on every run (0 edges, unfuzzable). We skip only the
  // degenerate size<3 case (the exact bug boundary) so the full parser code path
  // stays fuzzable; the underread itself is a real upstream defect (documented).
  if (size < 3) return 0;

  Parser *pparser = Parser::create();
  if (!pparser) return 0;

  FuzzConsumer consumer;
  pparser->addConsumer(&consumer);
  pparser->process(data, size);
  pparser->releaseConsumer(&consumer);

  Parser::release(pparser);
  return 0;
}
