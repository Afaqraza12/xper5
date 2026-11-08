package com.sog05.root;

oneway interface IRootCallback {
    void onLog(String line);
    void onComplete(int exitCode);
}
