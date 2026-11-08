package com.sog05.root

import android.content.Context
import android.os.Process
import androidx.annotation.Keep
import java.io.File

/**
 * Runs inside the Shizuku UserService process: uid = shell (2000), no seccomp.
 *
 * This is the ONLY place the pipeline can run, because:
 *  - the exploit must execute as `shell`, and an app process cannot;
 *  - `insmod` must run as root, which the exploit grants to *this* process.
 *
 * Pipeline:
 *   1. exec libgl.so            -> temp root in this process
 *   2. exec libgl.so (leak)     -> live KASLR text_base
 *   3. kspatch                  -> rebase the 34 ABS symbols in kernelsu.ko
 *   4. insmod                   -> load KernelSU
 *   5. crown manager            -> write ksu_debug_manager_appid
 */
@Keep
class RootService(private val context: Context) : IRootService.Stub() {

    @Volatile
    private var running = false

    override fun destroy() {
        if (!running) kotlin.system.exitProcess(0)
    }

    override fun runPipeline(skipExploit: Boolean, callback: IRootCallback) {
        if (running) {
            callback.onLog("<e> a run is already in progress")
            callback.onComplete(1)
            return
        }
        running = true
        Thread({
            val code = try {
                execute(skipExploit, callback)
            } catch (t: Throwable) {
                log(callback, "<e> fatal: ${t.message}")
                1
            } finally {
                running = false
            }
            callback.onComplete(code)
        }, "sog05-root").start()
    }

    private fun log(cb: IRootCallback, line: String) = runCatching { cb.onLog(line) }

    private fun execute(skipExploit: Boolean, cb: IRootCallback): Int {
        val uid = Process.myUid()
        log(cb, "<s> service uid=$uid (shell=${Process.SHELL_UID})")
        if (uid != Process.SHELL_UID) {
            log(cb, "<e> not running as shell; Shizuku UserService missing")
            return 1
        }
        val seccompOk = File("/proc/self/status").readLines()
            .firstOrNull { it.startsWith("Seccomp:") }
            ?.substringAfter(':')?.trim() == "0"
        log(cb, "<s> seccomp=${if (seccompOk) "disabled" else "FILTERED (exploit will fail)"}")
        if (!seccompOk) return 1

        // Work dir must be writable by shell.
        val work = File("/data/local/tmp/sog05")
        if (!work.isDirectory && !work.mkdirs()) {
            log(cb, "<e> cannot create ${work.absolutePath}")
            return 1
        }

        // The exploit binary hardcodes /data/local/tmp/su as its own entry point
        // and /data/local/tmp/gl_root_cmd / gl_root_out for its root daemon, so
        // it must be staged at exactly those paths (staging it elsewhere breaks
        // the symlink contract that makes `su -c ...` work).
        val native = context.applicationInfo.nativeLibraryDir
        val gl = stageExecutable(File(native, "libgl.so"), File("/data/local/tmp/gl"), cb)
        val kspatch = stageExecutable(File(native, "libkspatch.so"), File(work, "kspatch"), cb)
        if (gl == null || kspatch == null) {
            log(cb, "<e> missing or unstaged payloads")
            return 1
        }
        // /data/local/tmp/su must point at the exploit: that is what turns
        // argv[0] into `su` and routes commands to the root daemon.
        val su = File("/data/local/tmp/su")
        if (runCatching {
                if (su.exists() || su.toPath().isSymbolicLink()) su.delete()
                java.nio.file.Files.createSymbolicLink(su.toPath(), java.nio.file.Paths.get(gl.absolutePath))
                true
            }.getOrDefault(false).not()
        ) {
            log(cb, "<e> could not create ${su.absolutePath} -> ${gl.absolutePath}")
            return 1
        }
        log(cb, "<s> su shim ready: ${su.absolutePath} -> ${gl.absolutePath}")

        // Stage the KernelSU module out of assets. Always overwrite so a rebuilt
        // APK ships a freshly patched module rather than a stale one.
        val stagedKo = File(work, "kernelsu.ko")
        val stagedOk = runCatching {
            context.assets.open("kernelsu.ko").use { input ->
                stagedKo.outputStream().use { input.copyTo(it) }
            }
            true
        }.getOrElse {
            log(cb, "<e> cannot stage kernelsu.ko: ${it.message}")
            false
        }
        if (!stagedOk) return 1
        log(cb, "<s> staged kernelsu.ko (${stagedKo.length()} bytes)")

        if (alreadyLoaded()) {
            log(cb, "<s> kernelsu already loaded; crowning manager and finishing")
            crownManager(su, cb)
            return 0
        }

        // --- stage 1+2: exploit (also prints the KASLR leak) ---
        var textBase: String? = null
        if (!skipExploit) {
            log(cb, "<b> stage 1: running exploit")
            val out = File(work, "gl.log")
            val rc = run(listOf(gl.absolutePath), out, cb, env = mapOf("FP_DAEMON" to "1"))
            log(cb, "<s> exploit exited $rc")
            textBase = Regex("text_base=([0-9a-fA-F]+)")
                .find(out.readText())?.groupValues?.get(1)
            if (textBase == null) {
                log(cb, "<e> exploit did not report text_base; see ${out.absolutePath}")
                return 1
            }
            log(cb, "<s> live text_base=0x$textBase")
        }

        // If exploit was skipped, re-run in leak-only mode.
        if (textBase == null) {
            log(cb, "<b> stage 2: leaking text_base")
            val out = File(work, "leak.log")
            run(listOf(gl.absolutePath), out, cb, env = mapOf("DIAG_LEAK_ONLY" to "1"))
            textBase = Regex("text_base=([0-9a-fA-F]+)")
                .find(out.readText())?.groupValues?.get(1)
            if (textBase == null) {
                log(cb, "<e> leak failed")
                return 1
            }
        }

        // --- stage 3: patch module ---
        log(cb, "<b> stage 3: patching kernelsu.ko")
        val src = File(work, "kernelsu.ko")
        val dst = File(work, "kernelsu_live.ko")
        if (!src.isFile) {
            log(cb, "<e> kernelsu.ko not staged at ${src.absolutePath}")
            return 1
        }
        val patchLog = File(work, "kspatch.log")
        val prc = run(listOf(kspatch.absolutePath, src.absolutePath, dst.absolutePath, textBase), patchLog, cb)
        if (prc != 0 || !dst.isFile) {
            log(cb, "<e> kspatch failed ($prc)")
            return 1
        }

        // --- stage 4: load module ---
        // Every privileged step goes through the `su` shim: this process is
        // uid=shell, so a direct `/system/bin/insmod` would be rejected (EPERM).
        if (!su.canExecute()) {
            log(cb, "<e> ${su.absolutePath} is not executable (no temporary root)")
            return 1
        }
        log(cb, "<b> stage 4: loading kernelsu")
        val insLog = File(work, "insmod.log")
        val irc = run(listOf(su.absolutePath, "-c", "insmod ${dst.absolutePath}"), insLog, cb)
        Thread.sleep(1500)
        if (!alreadyLoaded()) {
            log(cb, "<e> insmod did not load kernelsu (rc=$irc); see ${insLog.absolutePath}")
            return 1
        }
        log(cb, "<s> kernelsu is live")

        // KernelSU wants its data dir to exist before the manager starts.
        val mkdirLog = File(work, "mkdir.log")
        run(listOf(su.absolutePath, "-c", "mkdir -p /data/adb/ksu && chmod 755 /data/adb /data/adb/ksu"), mkdirLog, cb)

        // --- stage 5: crown ---
        crownManager(su, cb)
        log(cb, "<s> done. Open the manager app to grant root.")
        return 0
    }

    private fun alreadyLoaded(): Boolean = runCatching {
        File("/proc/modules").readLines().any { it.startsWith("kernelsu ") }
    }.getOrDefault(false)

    /** Copies a packaged payload into the shared work dir and marks it executable. */
    private fun stageExecutable(from: File, to: File, cb: IRootCallback): File? {
        if (!from.isFile) {
            log(cb, "<e> missing packaged payload: ${from.name}")
            return null
        }
        return runCatching {
            // A previous run may have left a root-owned copy behind; delete it
            // first so the copy cannot fail with EACCES.
            if (to.exists() && !to.delete()) {
                runCatching {
                    Runtime.getRuntime().exec(arrayOf("rm", "-f", to.absolutePath)).waitFor()
                }
            }
            from.copyTo(to, overwrite = true)
            to.setExecutable(true, false)
            to.setReadable(true, false)
            if (!to.canExecute()) {
                // Fall back to chmod through the shell.
                Runtime.getRuntime().exec(arrayOf("chmod", "755", to.absolutePath)).waitFor()
            }
            log(cb, "<s> staged ${to.name} (${to.length()} bytes)")
            to
        }.onFailure { log(cb, "<e> staging ${to.name} failed: ${it.message}") }.getOrNull()
    }

    private fun crownManager(su: File, cb: IRootCallback) {
        val pm = context.packageManager
        val candidates = listOf(
            "com.resukisu.resukisu", "com.originsu.manager",
            "me.weishu.kernelsu", "com.sukisu.ultra",
        )
        val param = "/sys/module/kernelsu/parameters/ksu_debug_manager_appid"
        for (pkg in candidates) {
            val uidv = runCatching { pm.getApplicationInfo(pkg, 0).uid }.getOrNull() ?: continue
            val ok = runCatching {
                run(listOf(su.absolutePath, "-c", "echo $uidv > $param"), File("/data/local/tmp/sog05/crown.log"), cb) == 0
            }.getOrDefault(false)
            if (ok) {
                log(cb, "<s> crowned $pkg (uid $uidv)")
            } else {
                log(cb, "<e> could not crown $pkg (write to $param failed)")
            }
            return
        }
        log(cb, "<e> no known manager package installed")
    }

    private fun run(cmd: List<String>, out: File, cb: IRootCallback, env: Map<String, String> = emptyMap()): Int {
        log(cb, "<b> $ ${cmd.joinToString(" ")}")
        return try {
            // Truncate first: appending across runs would let a stale
            // `text_base=` line from a previous boot match the regex.
            val pb = ProcessBuilder(cmd)
                .directory(File("/data/local/tmp"))
                .redirectErrorStream(true)
                .redirectOutput(ProcessBuilder.Redirect.to(out))
            pb.environment().putAll(env)
            pb.start().waitFor()
        } catch (t: Throwable) {
            log(cb, "<e> exec failed: ${t.message}")
            -1
        }
    }
}
