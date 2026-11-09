package com.sog05.root

import android.content.Context
import android.os.Process
import androidx.annotation.Keep
import java.io.File
import java.nio.file.Files
import java.nio.file.Paths
import java.util.zip.ZipFile

/**
 * Runs inside the Shizuku UserService process: uid = shell (2000), no seccomp.
 *
 * Pipeline:
 *   1. Check / gain temporary root via libgl.so (or use existing su daemon)
 *   2. Leak live KASLR text_base (via DIAG_LEAK_ONLY)
 *   3. kspatch -> rebase the 34 ABS symbols in kernelsu.ko
 *   4. Clean legacy Magisk artifacts and setup /data/adb/ksu
 *   5. insmod -> load KernelSU into live kernel
 *   6. Crown manager (ReSukiSU uid 10419) -> write ksu_debug_manager_appid
 */
@Keep
class RootService : IRootService.Stub {

    private var context: Context? = null

    @Volatile
    private var running = false

    @Keep
    constructor() : super()

    @Keep
    constructor(context: Context) : super() {
        this.context = context
    }

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
        val seccompOk = runCatching {
            File("/proc/self/status").readLines()
                .firstOrNull { it.startsWith("Seccomp:") }
                ?.substringAfter(':')?.trim() == "0"
        }.getOrDefault(false)
        log(cb, "<s> seccomp=${if (seccompOk) "disabled" else "FILTERED (exploit will fail)"}")
        if (!seccompOk) return 1

        // Work dir must be writable by shell.
        val work = File("/data/local/tmp/sog05")
        if (!work.isDirectory && !work.mkdirs()) {
            log(cb, "<e> cannot create ${work.absolutePath}")
            return 1
        }

        // Locate or extract native payloads
        val gl = stageExecutable("libgl.so", File("/data/local/tmp/gl"), cb)
        val kspatch = stageExecutable("libkspatch.so", File(work, "kspatch"), cb)
        if (gl == null || kspatch == null) {
            log(cb, "<e> missing or unstaged payloads")
            return 1
        }

        // Setup /data/local/tmp/su -> /data/local/tmp/gl
        val su = File("/data/local/tmp/su")
        if (runCatching {
                if (su.exists() || Files.isSymbolicLink(su.toPath())) {
                    if (!su.delete()) {
                        Runtime.getRuntime().exec(arrayOf("rm", "-f", su.absolutePath)).waitFor()
                    }
                }
                Files.createSymbolicLink(su.toPath(), Paths.get(gl.absolutePath))
                true
            }.getOrDefault(false).not()
        ) {
            runCatching {
                Runtime.getRuntime().exec(arrayOf("ln", "-sf", gl.absolutePath, su.absolutePath)).waitFor()
            }
        }
        if (!su.exists() && !Files.isSymbolicLink(su.toPath())) {
            log(cb, "<e> could not create ${su.absolutePath} -> ${gl.absolutePath}")
            return 1
        }
        log(cb, "<s> su shim ready: ${su.absolutePath} -> ${gl.absolutePath}")

        // Stage KernelSU module out of assets or APK
        val stagedKo = File(work, "kernelsu.ko")
        if (!stageKernelSu(stagedKo, cb)) {
            log(cb, "<e> cannot stage kernelsu.ko")
            return 1
        }
        log(cb, "<s> staged kernelsu.ko (${stagedKo.length()} bytes)")

        // Check if root daemon is already alive
        val hasRoot = runCatching {
            val p = Runtime.getRuntime().exec(arrayOf(su.absolutePath, "-c", "id"))
            p.waitFor()
            p.inputStream.bufferedReader().readText().contains("uid=0")
        }.getOrDefault(false)

        if (alreadyLoaded()) {
            log(cb, "<b> kernelsu already loaded; checking if reload needed")
            val rmLog = File(work, "rmmod.log")
            if (hasRoot) {
                run(listOf(su.absolutePath, "-c", "rmmod kernelsu"), rmLog, cb)
                Thread.sleep(800)
            }
            if (alreadyLoaded()) {
                log(cb, "<s> kernelsu is active in kernel; crowning manager")
                if (hasRoot) crownManager(su, cb)
                return 0
            }
            log(cb, "<s> previous module unloaded cleanly")
        }

        // --- stage 1: gain root if not already active ---
        if (!hasRoot && !skipExploit) {
            log(cb, "<b> stage 1: running GhostLock exploit")
            val out = File(work, "gl.log")
            val rc = run(listOf(gl.absolutePath), out, cb)
            log(cb, "<s> exploit finished (exit=$rc)")
            Thread.sleep(1000)
        }

        // --- stage 2: leak live KASLR text_base ---
        log(cb, "<b> stage 2: leaking KASLR text_base")
        val leakLog = File(work, "leak.log")
        run(listOf(gl.absolutePath), leakLog, cb, env = mapOf("DIAG_LEAK_ONLY" to "1"))
        val leakText = runCatching { leakLog.readText() }.getOrDefault("")
        val textBase = Regex("text_base=([0-9a-fA-F]+)").find(leakText)?.groupValues?.get(1)
        if (textBase == null) {
            log(cb, "<e> failed to leak text_base; see ${leakLog.absolutePath}")
            return 1
        }
        log(cb, "<s> live text_base=0x$textBase")

        // --- stage 3: patch kernelsu.ko symbols ---
        log(cb, "<b> stage 3: patching kernelsu.ko with live KASLR slide")
        val dst = File(work, "kernelsu_live.ko")
        val patchLog = File(work, "kspatch.log")
        val prc = run(listOf(kspatch.absolutePath, stagedKo.absolutePath, dst.absolutePath, textBase), patchLog, cb)
        if (prc != 0 || !dst.isFile || dst.length() == 0L) {
            log(cb, "<e> kspatch failed ($prc); see ${patchLog.absolutePath}")
            return 1
        }
        log(cb, "<s> patched kernelsu_live.ko (${dst.length()} bytes)")

        // --- stage 4: clean legacy Magisk & prepare /data/adb/ksu ---
        val cleanLog = File(work, "cleanup.log")
        run(listOf(su.absolutePath, "-c", "rm -rf /data/local/tmp/magisk* /data/adb/magisk"), cleanLog, cb)
        val mkdirLog = File(work, "mkdir.log")
        run(listOf(su.absolutePath, "-c", "mkdir -p /data/adb/ksu && chmod 755 /data/adb /data/adb/ksu && chown -R 0:0 /data/adb"), mkdirLog, cb)

        // --- stage 5: insert KernelSU module ---
        log(cb, "<b> stage 5: inserting KernelSU module into kernel")
        val insLog = File(work, "insmod.log")
        val irc = run(listOf(su.absolutePath, "-c", "insmod ${dst.absolutePath}"), insLog, cb)
        Thread.sleep(1500)

        if (!alreadyLoaded()) {
            log(cb, "<e> insmod failed (rc=$irc); see ${insLog.absolutePath}")
            val dmesgErr = runCapture(listOf(su.absolutePath, "-c", "dmesg | grep -i -E '(kernelsu|module)' | tail -n 15"))
            if (dmesgErr.isNotBlank()) {
                dmesgErr.lines().filter { it.isNotBlank() }.forEach { log(cb, "<d> $it") }
            }
            return 1
        }
        log(cb, "<s> KernelSU loaded successfully!")

        // Show kernel initialization log
        val klog = runCapture(listOf(su.absolutePath, "-c", "dmesg | grep -i kernelsu | tail -n 8"))
        if (klog.isNotBlank()) {
            klog.lines().filter { it.isNotBlank() }.forEach { log(cb, "<k> $it") }
        }

        // --- stage 6: crown manager app ---
        crownManager(su, cb)

        // --- stage 7: initialize KernelSU userspace daemon & modules ---
        val ksud = File("/data/adb/ksud")
        if (ksud.exists() || runCatching { runCapture(listOf(su.absolutePath, "-c", "[ -f /data/adb/ksud ] && echo ok")).contains("ok") }.getOrDefault(false)) {
            log(cb, "<b> stage 7: starting KernelSU modules daemon")
            val ksudLog = File(work, "ksud_init.log")
            run(listOf(su.absolutePath, "-c", "chmod 755 /data/adb/ksud && nohup /data/adb/ksud post-fs-data >/dev/null 2>&1 &"), ksudLog, cb)
            Thread.sleep(1500)
            run(listOf(su.absolutePath, "-c", "nohup /data/adb/ksud services >/dev/null 2>&1 &"), ksudLog, cb)
            run(listOf(su.absolutePath, "-c", "nohup /data/adb/ksud boot-completed >/dev/null 2>&1 &"), ksudLog, cb)
            log(cb, "<s> KernelSU modules daemon initialized")
        }

        log(cb, "<s> SUCCESS! Open ReSukiSU to manage superuser permissions.")
        return 0
    }

    private fun alreadyLoaded(): Boolean = runCatching {
        File("/proc/modules").readLines().any { it.startsWith("kernelsu ") }
    }.getOrDefault(false)

    private fun getApkPath(): String? {
        context?.applicationInfo?.sourceDir?.let { return it }
        return runCatching {
            val p = Runtime.getRuntime().exec(arrayOf("pm", "path", "com.sog05.root"))
            val out = p.inputStream.bufferedReader().readText().trim()
            out.substringAfter("package:").trim().takeIf { it.isNotEmpty() }
        }.getOrNull()
    }

    private fun findNativeFile(libName: String): File? {
        context?.applicationInfo?.nativeLibraryDir?.let {
            val f = File(it, libName)
            if (f.isFile) return f
        }
        val apkPath = getApkPath() ?: return null
        val libDir = File(File(apkPath).parentFile, "lib/arm64")
        val f = File(libDir, libName)
        if (f.isFile) return f
        return null
    }

    /** Stages native executable into target path and sets permissions 755. */
    private fun stageExecutable(libName: String, to: File, cb: IRootCallback): File? {
        val existing = findNativeFile(libName)
        if (existing != null && existing.isFile) {
            return copyAndChmod(existing, to, cb)
        }
        // Fallback: extract directly from the APK zip (lib/arm64-v8a/<libName>)
        val apkPath = getApkPath()
        if (apkPath != null) {
            val ok = runCatching {
                ZipFile(File(apkPath)).use { zip ->
                    val entry = zip.getEntry("lib/arm64-v8a/$libName")
                        ?: zip.getEntry("assets/$libName")
                        ?: return@runCatching false
                    zip.getInputStream(entry).use { input ->
                        to.outputStream().use { input.copyTo(it) }
                    }
                    true
                }
            }.getOrDefault(false)
            if (ok && to.isFile) {
                to.setExecutable(true, false)
                to.setReadable(true, false)
                runCatching { Runtime.getRuntime().exec(arrayOf("chmod", "755", to.absolutePath)).waitFor() }
                log(cb, "<s> extracted ${to.name} from APK (${to.length()} bytes)")
                return to
            }
        }
        log(cb, "<e> missing packaged payload: $libName")
        return null
    }

    private fun copyAndChmod(from: File, to: File, cb: IRootCallback): File? {
        return runCatching {
            if (to.exists() && !to.delete()) {
                runCatching { Runtime.getRuntime().exec(arrayOf("rm", "-f", to.absolutePath)).waitFor() }
            }
            from.copyTo(to, overwrite = true)
            to.setExecutable(true, false)
            to.setReadable(true, false)
            if (!to.canExecute()) {
                Runtime.getRuntime().exec(arrayOf("chmod", "755", to.absolutePath)).waitFor()
            }
            log(cb, "<s> staged ${to.name} (${to.length()} bytes)")
            to
        }.onFailure { log(cb, "<e> staging ${to.name} failed: ${it.message}") }.getOrNull()
    }

    private fun stageKernelSu(dst: File, cb: IRootCallback): Boolean {
        // Try AssetManager first
        if (context != null) {
            val ok = runCatching {
                context!!.assets.open("kernelsu.ko").use { input ->
                    dst.outputStream().use { input.copyTo(it) }
                }
                true
            }.getOrDefault(false)
            if (ok && dst.isFile && dst.length() > 0) return true
        }

        // Fallback 1: Extract directly from APK zip
        val apkPath = getApkPath()
        if (apkPath != null) {
            val ok = runCatching {
                ZipFile(File(apkPath)).use { zip ->
                    val entry = zip.getEntry("assets/kernelsu.ko") ?: return@runCatching false
                    zip.getInputStream(entry).use { input ->
                        dst.outputStream().use { input.copyTo(it) }
                    }
                    true
                }
            }.getOrDefault(false)
            if (ok && dst.isFile && dst.length() > 0) return true
        }

        // Fallback 2: Check if /data/local/tmp/kernelsu.ko exists
        val fallback = File("/data/local/tmp/kernelsu.ko")
        if (fallback.isFile && fallback.length() > 0) {
            runCatching {
                fallback.copyTo(dst, overwrite = true)
                return true
            }
        }
        return false
    }

    private fun getUidFromShell(pkg: String): Int? {
        return runCatching {
            val p = Runtime.getRuntime().exec(arrayOf("sh", "-c", "grep -m1 ^$pkg /data/system/packages.list 2>/dev/null || pm list packages -U 2>/dev/null | grep $pkg"))
            val text = p.inputStream.bufferedReader().readText()
            p.waitFor()
            Regex("[0-9]+").findAll(text).map { it.value.toInt() }.lastOrNull()
        }.getOrNull()
    }

    private fun crownManager(su: File, cb: IRootCallback) {
        val candidates = listOf(
            "com.resukisu.resukisu",
            "com.originsu.manager",
            "me.weishu.kernelsu",
            "com.sukisu.ultra",
        )
        val param = "/sys/module/kernelsu/parameters/ksu_debug_manager_appid"

        for (pkg in candidates) {
            var uidv: Int? = null
            if (context != null) {
                uidv = runCatching { context!!.packageManager.getApplicationInfo(pkg, 0).uid }.getOrNull()
            }
            if (uidv == null) {
                uidv = getUidFromShell(pkg)
            }
            // Fallback for default ReSukiSU UID if installed
            if (uidv == null && pkg == "com.resukisu.resukisu") {
                uidv = 10419
            }
            if (uidv == null) continue

            val ok = runCatching {
                run(listOf(su.absolutePath, "-c", "echo $uidv > $param"), File("/data/local/tmp/sog05/crown.log"), cb) == 0
            }.getOrDefault(false)

            if (ok) {
                log(cb, "<s> crowned $pkg (uid $uidv)")
                return
            }
        }
        log(cb, "<e> could not crown manager (no supported manager app found)")
    }

    private fun run(cmd: List<String>, out: File, cb: IRootCallback, env: Map<String, String> = emptyMap()): Int {
        log(cb, "<b> $ ${cmd.joinToString(" ")}")
        return try {
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

    private fun runCapture(cmd: List<String>): String {
        return runCatching {
            val pb = ProcessBuilder(cmd)
                .directory(File("/data/local/tmp"))
                .redirectErrorStream(true)
            val p = pb.start()
            val text = p.inputStream.bufferedReader().readText()
            p.waitFor()
            text
        }.getOrDefault("")
    }
}
