// mayhem/oracle/kat_main.cpp — entry point of the known-answer runners built from
// mayhem/oracle/observe.cpp (upstream's suite with the expected half of every assertion removed).
//
//   <runner> <nonce> <dir> <CASE>   run one test case and print its records (see kat.h)
//   <runner> --list                 print the case names
//
// <dir>/samples/ holds the HEVC streams. Each observation prints "@@ <nonce> <CASE> <seq> <line>
// <value>" (see kat.h); after the case returns, the runner prints "@@ <nonce> <CASE> END". Every
// line is flushed as it is written, so a crash keeps the records printed before it. The runner
// holds no answers and decides nothing; mayhem/test.sh does.
#include <cstdio>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

#include "kat.h"

#include "Params.h"

namespace {
std::vector<std::pair<const char *, void (*)()> > &cases() {
  static std::vector<std::pair<const char *, void (*)()> > v;
  return v;
}
const char *g_nonce = "";
const char *g_case = "";
std::string g_dir;
unsigned long g_seq = 0;
}  // namespace

kat::Reg::Reg(const char *name, void (*fn)()) { cases().push_back(std::make_pair(name, fn)); }

std::string kat::num(long long v) {
  char b[32];
  std::snprintf(b, sizeof b, "%lld", v);
  return b;
}

std::string kat::num(unsigned long long v) {
  char b[32];
  std::snprintf(b, sizeof b, "%llu", v);
  return b;
}

void kat::record(int line, const std::string &value) {
  std::printf("@@ %s %s %lu %d %s\n", g_nonce, g_case, ++g_seq, line, value.c_str());
  std::fflush(stdout);
}

std::string getSourceDir() { return g_dir; }

int main(int argc, char **argv) {
  if (argc == 2 && std::strcmp(argv[1], "--list") == 0) {
    for (std::size_t i = 0; i < cases().size(); ++i) std::printf("%s\n", cases()[i].first);
    return 0;
  }
  if (argc != 4) {
    std::fprintf(stderr, "usage: %s <nonce> <dir> <CASE> | --list\n", argv[0]);
    return 2;
  }
  g_nonce = argv[1];
  g_dir = argv[2];
  g_case = argv[3];
  for (std::size_t i = 0; i < cases().size(); ++i) {
    if (std::strcmp(cases()[i].first, g_case) == 0) {
      cases()[i].second();
      std::printf("@@ %s %s END\n", g_nonce, g_case);
      std::fflush(stdout);
      return 0;
    }
  }
  std::fprintf(stderr, "unknown case %s\n", g_case);
  return 2;
}
