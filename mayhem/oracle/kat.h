// mayhem/oracle/kat.h -- the macros mayhem/oracle/observe.cpp (upstream's suite with the expected
// half of every assertion removed, see make-observe.py) uses in the known-answer runners that
// mayhem/test.sh drives.
//
// Nothing here knows an answer or decides pass or fail. Each KAT_OBS / KAT_OBS_RANGE prints the
// value of the parser-side expression of one upstream assertion, as a decimal integer (a range
// prints as <count>:<v1>,<v2>,...):
//   @@ <nonce> <case> <seq> <line> <value>
// mayhem/test.sh compares it with mayhem/oracle/expected.txt, which no runner is built from, and
// keeps every count itself.
#pragma once

#include <cstddef>
#include <string>
#include <type_traits>

namespace kat {

struct Reg {
  Reg(const char *name, void (*fn)());
};

void record(int line, const std::string &value);
std::string num(long long v);
std::string num(unsigned long long v);

template <class T>
typename std::enable_if<std::is_integral<T>::value && std::is_signed<T>::value, std::string>::type
fmt(const T &v) {
  return num(static_cast<long long>(v));
}

template <class T>
typename std::enable_if<std::is_integral<T>::value && !std::is_signed<T>::value, std::string>::type
fmt(const T &v) {
  return num(static_cast<unsigned long long>(v));
}

template <class T>
typename std::enable_if<std::is_enum<T>::value, std::string>::type fmt(const T &v) {
  typedef typename std::underlying_type<T>::type U;
  return fmt(static_cast<U>(v));
}

template <class It>
std::string fmt_range(It b, It e) {
  std::string body;
  std::size_t n = 0;
  for (; b != e; ++b, ++n) {
    if (n) body += ',';
    body += fmt(*b);
  }
  return num(static_cast<unsigned long long>(n)) + ":" + body;
}

// noinline: one out-of-line copy per type, not 1777 inlined string builds in the case bodies
// (that made the -O3 compile of observe.cpp about 3x slower; it changes no printed value).
template <class A>
__attribute__((noinline)) void observe(int line, const A &a) {
  record(line, fmt(a));
}

template <class It>
__attribute__((noinline)) void observe_range(int line, It b, It e) {
  record(line, fmt_range(b, e));
}

}  // namespace kat

#define KAT_CASE(name)                                              \
  static void kat_case_##name();                                    \
  static ::kat::Reg kat_reg_##name(#name, &kat_case_##name);        \
  static void kat_case_##name()
#define KAT_OBS(a) ::kat::observe(__LINE__, (a))
#define KAT_OBS_RANGE(b, e) ::kat::observe_range(__LINE__, (b), (e))
