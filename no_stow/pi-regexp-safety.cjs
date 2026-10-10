// Warden 0.71.0's credential scanner can backtrack indefinitely on signed-URL
// values. Keep scanning enabled and let V8 fall back for eligible regexes.
require("node:v8").setFlagsFromString("--enable-experimental-regexp-engine-on-excessive-backtracks");
