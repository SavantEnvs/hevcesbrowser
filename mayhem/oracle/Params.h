// mayhem/oracle/Params.h — the pinned suite's "Params.h". Upstream's getSourceDir() returns the
// directory of the test sources; here it returns the directory mayhem/test.sh names on the command
// line, whose samples/ holds test.sh's SHA-checked copies of the HEVC streams.
#ifndef PARAMS_H_
#define PARAMS_H_

#include <string>

std::string getSourceDir();

#endif
