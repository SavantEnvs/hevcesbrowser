// mayhem/oracle/lsan_off.cc -- build-time LeakSanitizer off-switch (SPEC.md section 6.2 item 15)
// for the sanitized known-answer runners only (build-fuzz/hevc_kat, build-fuzz/hevc_kat_twin).
//
// The pinned upstream suite never frees the buffer it reads each stream into (observe.cpp:
// `char *pdata = new char[size];`), so with LeakSanitizer on every sanitized run would end in a
// leak report about the test code, not the parser. This turns off ONLY leak detection in those
// runners; ASan's memory-error checks and UBSan stay fully active, and no runtime option is set.
// The graded fuzz binaries do not link this file.
extern "C" int __lsan_is_turned_off() { return 1; }
