package com.sog05.root

import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import rikka.shizuku.Shizuku
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : AppCompatActivity() {

    private lateinit var status: TextView
    private lateinit var output: TextView
    private lateinit var rootButton: Button
    private val runner by lazy { ShizukuRunner(this) }
    private val logBuf = StringBuilder()

    private val permListener = Shizuku.OnRequestPermissionResultListener { _, result ->
        log("<s> permission result=$result")
        refresh()
    }
    private val binderListener = Shizuku.OnBinderReceivedListener { refresh() }
    private val binderDeadListener = Shizuku.OnBinderDeadListener { refresh() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Shizuku.addRequestPermissionResultListener(permListener)
        Shizuku.addBinderReceivedListenerSticky(binderListener)
        Shizuku.addBinderDeadListener(binderDeadListener)

        val pad = (16 * resources.displayMetrics.density).toInt()
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad, pad, pad)
        }
        status = TextView(this).apply { textSize = 15f }
        rootButton = Button(this).apply {
            text = "One-click root"
            setOnClickListener { start() }
        }
        output = TextView(this).apply {
            textSize = 11f
            setTextIsSelectable(true)
            typeface = android.graphics.Typeface.MONOSPACE
        }
        val scroll = ScrollView(this).apply { addView(output) }
        col.addView(status)
        col.addView(rootButton)
        col.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(col)
        refresh()
    }

    override fun onDestroy() {
        Shizuku.removeRequestPermissionResultListener(permListener)
        Shizuku.removeBinderReceivedListener(binderListener)
        Shizuku.removeBinderDeadListener(binderDeadListener)
        super.onDestroy()
    }

    private fun refresh() {
        when (runner.state()) {
            ShizukuRunner.State.READY -> {
                status.text = "Shizuku ready — tap to root"
                rootButton.isEnabled = true
                rootButton.text = "One-click root"
            }
            ShizukuRunner.State.PERMISSION_REQUIRED -> {
                status.text = "Shizuku needs permission"
                rootButton.isEnabled = true
                rootButton.text = "Grant Shizuku permission"
            }
            ShizukuRunner.State.NOT_RUNNING -> {
                status.text = "Shizuku is not running.\nStart Shizuku on device via Wireless Debugging, or via adb:\n  adb shell sh /sdcard/Android/data/moe.shizuku.privileged.api/start.sh"
                rootButton.isEnabled = false
                rootButton.text = "One-click root"
            }
            ShizukuRunner.State.NOT_INSTALLED -> {
                status.text = "Install the Shizuku app first"
                rootButton.isEnabled = false
            }
        }
    }

    private fun log(line: String) {
        val ts = SimpleDateFormat("HH:mm:ss", Locale.ROOT).format(Date())
        logBuf.append("[").append(ts).append("] ").append(line).append('\n')
        runOnUiThread { output.text = logBuf.toString() }
    }

    private fun start() {
        if (runner.state() == ShizukuRunner.State.PERMISSION_REQUIRED) {
            runner.requestPermission()
            return
        }
        if (runner.state() != ShizukuRunner.State.READY) {
            refresh()
            return
        }
        rootButton.isEnabled = false
        rootButton.text = "Running…"
        runner.run(
            skipExploit = false,
            onLog = ::log,
            onDone = { code ->
                runOnUiThread {
                    status.text = if (code == 0) "Root loaded" else "Failed (exit=$code)"
                    rootButton.isEnabled = true
                    rootButton.text = "One-click root"
                }
            },
        )
    }
}
