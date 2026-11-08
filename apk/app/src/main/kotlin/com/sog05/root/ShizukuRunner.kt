package com.sog05.root

import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import rikka.shizuku.Shizuku
import java.util.concurrent.atomic.AtomicBoolean

/** Binds the Shizuku UserService (uid=shell) that does the real work. */
class ShizukuRunner(private val context: Context) {

    enum class State { NOT_INSTALLED, NOT_RUNNING, PERMISSION_REQUIRED, READY }

    fun state(): State = try {
        if (!Shizuku.pingBinder()) State.NOT_RUNNING
        else if (Shizuku.getUid() != Process.SHELL_UID) State.NOT_RUNNING
        else if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) State.PERMISSION_REQUIRED
        else State.READY
    } catch (_: Throwable) {
        NOT_INSTALLED
    }

    fun requestPermission() {
        if (Shizuku.pingBinder() &&
            Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED
        ) {
            Shizuku.requestPermission(PERM_REQUEST)
        }
    }

    fun run(skipExploit: Boolean, onLog: (String) -> Unit, onDone: (Int) -> Unit) {
        val args = Shizuku.UserServiceArgs(
            ComponentName(context.packageName, RootService::class.java.name),
        )
            .daemon(false)
            .processNameSuffix("root")
            .debuggable(false)
            .version(1)

        val handler = Handler(Looper.getMainLooper())
        val finished = AtomicBoolean(false)
        lateinit var conn: ServiceConnection

        conn = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                onLog("<b> service connected")
                val svc = IRootService.Stub.asInterface(binder)
                val cb = object : IRootCallback.Stub() {
                    override fun onLog(line: String) = onLog(line)
                    override fun onComplete(exitCode: Int) {
                        if (finished.compareAndSet(false, true)) {
                            onLog("<b> finished (exit=$exitCode)")
                            onDone(exitCode)
                            runCatching { Shizuku.unbindUserService(args, conn, true) }
                        }
                    }
                }
                runCatching { svc.runPipeline(skipExploit, cb) }.onFailure {
                    onLog("<e> ${it.message}")
                    onDone(1)
                }
            }

            override fun onServiceDisconnected(name: ComponentName) {
                if (finished.compareAndSet(false, true)) {
                    onLog("<e> service disconnected")
                    onDone(1)
                }
            }
        }

        onLog("<b> binding UserService")
        runCatching { Shizuku.bindUserService(args, conn) }.onFailure {
            onLog("<e> bind failed: ${it.message}")
            onDone(1)
            return
        }

        handler.postDelayed({
            if (finished.compareAndSet(false, true)) {
                onLog("<e> connect timeout")
                onDone(1)
            }
        }, 10_000)
    }

    companion object {
        const val PERM_REQUEST = 0x5057
    }
}
