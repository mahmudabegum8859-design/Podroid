/*
 * Podroid - Rootless Podman for Android
 * Copyright (C) 2024-2026 Podroid contributors
 *
 * AppLogger — writes a human-readable, per-second diagnostic stream to
 * /storage/emulated/0/openDemon/log.txt on the device's external storage so
 * a user can inspect "what the app is doing / what the VM is doing / what
 * problems occur" without adb. Created on app start; runs for the app's
 * lifetime on a dedicated IO scope.
 *
 * The file is only created when the app holds all-files access
 * (MANAGE_EXTERNAL_STORAGE, already declared in the manifest). If that
 * permission is denied the writes silently no-op — logging never crashes the
 * app. Every line is timestamped; a state/boot transition is recorded as a
 * PROBLEM-less STATE line, explicit errors/warnings are buffered into the
 * per-tick PROBLEM field.
 */
package com.excp.podroid.util

import android.os.Environment
import com.excp.podroid.engine.VmEngine
import com.excp.podroid.engine.VmState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.ConcurrentLinkedQueue
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AppLogger @Inject constructor(
    private val engine: VmEngine,
) {
    private val dir: File = File(Environment.getExternalStorageDirectory(), "openDemon")
    private val logFile: File get() = File(dir, "log.txt")

    // Recent explicit problems/warnings, drained into each tick's PROBLEM field.
    private val problems = ConcurrentLinkedQueue<String>()

    private val dateFmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
    private val jobGuard = Any()

    @Volatile private var job: kotlinx.coroutines.Job? = null

    /** Begin the per-second logging loop. Safe to call repeatedly. */
    fun start(scope: CoroutineScope) {
        ensureDir()
        synchronized(jobGuard) {
            if (job?.isActive == true) return
            job = scope.launch(Dispatchers.IO) {
                var lastState = ""
                var lastStage = ""
                appendLineToFile(
                    "${dateFmt.format(Date())} | INFO | AppLogger | logging started; " +
                        "folder=${dir.absolutePath} exists=${dir.exists()}"
                )
                while (isActive) {
                    val st = engine.state.value
                    val stage = engine.bootStage.value
                    val stStr = stateString(st)

                    // Record meaningful transitions (VM start/stop/error, boot-stage
                    // advance) as discrete events so the long, otherwise-identical
                    // per-second lines still reveal what changed.
                    if (stStr != lastState) {
                        problems.add("STATE -> $stStr")
                        lastState = stStr
                    }
                    if (stage != lastStage) {
                        problems.add("BOOT -> ${stage.ifEmpty { "(idle)" }}")
                        lastStage = stage
                    }

                    writeTick(stStr, stage)
                    delay(1000)
                }
            }
        }
    }

    private fun stateString(st: VmState): String = when (st) {
        is VmState.Idle -> "IDLE"
        is VmState.Starting -> "STARTING"
        is VmState.Running -> "RUNNING"
        is VmState.Stopped -> "STOPPED"
        is VmState.Error -> "ERROR(${st.message})"
    }

    private fun writeTick(stateStr: String, stage: String) {
        val ts = dateFmt.format(Date())
        val sb = StringBuilder()
        sb.append("$ts | APP: $stateStr")
        if (stage.isNotEmpty()) sb.append(" | VM_BOOT: $stage")

        // Surface the guest's most recent console line so "what is the VM doing"
        // is visible even without opening the terminal.
        val console = engine.consoleText.value
        if (console.isNotEmpty()) {
            val lastLine = console.substringAfterLast('\n').trim()
            if (lastLine.isNotEmpty()) sb.append(" | VM_CONSOLE: ").append(lastLine.take(200))
        }

        var p = problems.poll()
        while (p != null) {
            sb.append(" | PROBLEM: ").append(p)
            p = problems.poll()
        }
        appendLineToFile(sb.toString())
    }

    fun i(tag: String, msg: String) =
        appendLineToFile("${dateFmt.format(Date())} | INFO | $tag | $msg")

    fun w(tag: String, msg: String) {
        appendLineToFile("${dateFmt.format(Date())} | WARN | $tag | $msg")
        problems.add("[$tag] WARN: $msg")
    }

    fun e(tag: String, msg: String, e: Throwable? = null) {
        val m = if (e != null && !e.message.isNullOrEmpty()) "$msg : ${e.message}" else msg
        appendLineToFile("${dateFmt.format(Date())} | ERROR | $tag | $m")
        problems.add("[$tag] ERROR: $m")
    }

    /** Ensure the external log folder exists. No-op on failure (permission etc.). */
    private fun ensureDir() {
        runCatching { if (!dir.exists()) dir.mkdirs() }
    }

    @Synchronized
    private fun appendLineToFile(line: String) {
        try {
            if (!dir.exists()) dir.mkdirs()
            if (!dir.exists()) return // permission not granted — skip silently
            logFile.appendText(line + "\n")
        } catch (_: Exception) {
            // Never let logging crash the app.
        }
    }
}
