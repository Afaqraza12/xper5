package com.sog05.root;

import com.sog05.root.IRootCallback;

interface IRootService {
    void destroy() = 16777114;
    void runPipeline(boolean skipExploit, IRootCallback callback) = 2;
}
