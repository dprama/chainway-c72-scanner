package com.example.chainway_c72_scanner

import android.app.Activity
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.KeyEvent
import android.view.WindowManager
import com.rscja.barcode.BarcodeDecoder
import com.rscja.barcode.BarcodeFactory
import com.rscja.barcode.BarcodeUtility
import com.rscja.deviceapi.RFIDWithUHFUART
import com.rscja.deviceapi.entity.BarcodeEntity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/** SDK commands are serialized. Vendor callback threads only collect results. */
class ChainwayScanner(private val activity: Activity) : EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadScheduledExecutor()
    private var sink: EventChannel.EventSink? = null
    private var barcode: BarcodeDecoder? = null
    private var uhf: RFIDWithUHFUART? = null
    private var timeout: ScheduledFuture<*>? = null
    private var tone: ToneGenerator? = null
    private var lastTone = 0L
    @Volatile private var generation = 0
    private var modeSelected = false
    @Volatile private var inForeground = false
    @Volatile private var enabled = true
    @Volatile private var destroyed = false
    @Volatile private var ready = false
    @Volatile private var scanning = false
    @Volatile private var mode = "barcode"
    @Volatile var sound = true
        set(value) {
            if (mode == "barcode" && ready) BarcodeUtility.getInstance().enablePlaySuccessSound(activity, value)
            field = value
        }
    private var power: Int? = null
    private var region: Int? = null
    @Volatile private var writerActive = false
    private val epcWriter = EpcWriter(
        { checkNotNull(uhf) }, { checkWriterReady() }, { generation }
    )
    private val heldKeys = mutableSetOf<Int>()
    private var triggerOwnsScan = false
    private val pending = linkedMapOf<String, MutableMap<String, Any?>>()
    // Official UHF demo: BaseTabFragmentActivity.onKeyDown.
    private val triggerKeys = setOf(139, 280, 291, 293, 294, 311, 312, 313, 315, 591, 593, 594, 596)

    init { worker.scheduleWithFixedDelay({ flush() }, 80, 80, TimeUnit.MILLISECONDS) }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        worker.execute { status("idle") }
    }
    override fun onCancel(arguments: Any?) {
        sink = null
        enabled = false
        if (!worker.isShutdown) worker.execute { safely { closeHardware() } }
    }

    fun command(result: MethodChannel.Result, action: ChainwayScanner.() -> Unit) {
        worker.execute {
            try { action(); main.post { result.success(null) } }
            catch (e: Throwable) {
                fail(e)
                main.post { result.error("SCANNER", describe(e), null) }
            }
        }
    }

    fun valueCommand(result: MethodChannel.Result, action: ChainwayScanner.() -> Any?) {
        worker.execute {
            try { val value = action(); main.post { result.success(value) } }
            catch (e: Throwable) {
                val code = if (e is EpcWriter.ReadFailure) "EPC_READ" else "EPC"
                main.post { result.error(code, describe(e), null) }
            }
        }
    }

    fun beginEpcWrite() {
        check(mode == "rfid" && ready && enabled && inForeground) { "Connect UHF before opening the EPC writer" }
        stop()
        epcWriter.invalidate()
        writerActive = true
        triggerOwnsScan = false
    }

    fun endEpcWrite() {
        epcWriter.invalidate()
        writerActive = false
        triggerOwnsScan = false
    }

    private fun checkWriterReady() {
        check(writerActive && enabled && inForeground && ready && mode == "rfid" && !scanning) {
            "EPC writer is not connected. Return to Scan, connect UHF and open Write EPC again"
        }
    }

    fun inspectEpc(epc: String, password: String): Map<String, Any?> = epcWriter.inspect(epc, password)
    fun writeEpc(token: String, epc: String): Map<String, Any?> = epcWriter.write(token, epc)

    fun selectMode(value: String) {
        check(!writerActive) { "Close the EPC writer before changing scanner mode" }
        require(value == "barcode" || value == "rfid") { "Unknown scan mode" }
        closeHardware()
        mode = value
        modeSelected = true
        if (enabled && inForeground) openHardware() else status("paused")
    }
    fun enable(value: Boolean) {
        enabled = value
        if (!value) closeHardware()
        else if (inForeground && modeSelected && !ready) openHardware()
    }
    fun foreground(value: Boolean) {
        inForeground = value
        if (!value) heldKeys.clear()
        worker.execute {
            safely {
                triggerOwnsScan = false
                if (!value) closeHardware()
                else if (enabled && modeSelected && !ready) openHardware()
            }
        }
    }

    fun handleTrigger(event: KeyEvent): Boolean {
        if (event.keyCode !in triggerKeys) return false
        if (writerActive) return true
        if (!enabled || !inForeground) { heldKeys.clear(); return false }
        if (event.action == KeyEvent.ACTION_DOWN) {
            if (event.repeatCount == 0 && heldKeys.add(event.keyCode) && heldKeys.size == 1) {
                worker.execute {
                    safely {
                        triggerOwnsScan = !scanning
                        if (triggerOwnsScan) start()
                    }
                }
            }
        } else if (event.action == KeyEvent.ACTION_UP) {
            heldKeys.remove(event.keyCode)
            if (heldKeys.isEmpty()) worker.execute {
                safely { if (triggerOwnsScan) stop(); triggerOwnsScan = false }
            }
        }
        return true
    }

    private fun openHardware() {
        status("opening")
        try {
            if (mode == "barcode") {
                val reader = BarcodeFactory.getInstance().barcodeDecoder
                    ?: error("No supported built-in barcode engine was found")
                barcode = reader
                check(reader.open(activity)) { "The barcode engine could not be opened" }
                reader.setTimeOut(8) // Official API uses seconds.
                BarcodeUtility.getInstance().enablePlaySuccessSound(activity, sound)
            } else {
                // KeyboardEmulator may hold its own UHF UART even after barcode.close().
                // Release it through the vendor API before taking direct SDK ownership.
                BarcodeUtility.getInstance().closeKeyboardHelper(activity)
                SystemClock.sleep(750) // Its broadcast receiver releases hardware asynchronously.
                val reader = RFIDWithUHFUART.getInstance() ?: error("No UHF module was found")
                uhf = reader
                check(reader.init(activity)) { "The UHF module could not be opened" }
                check(reader.setEPCMode()) { "The UHF module could not select EPC inventory" }
                power = reader.power.takeIf { it >= 0 }
                region = reader.frequencyMode.takeIf { it >= 0 }
            }
            ready = true
            status("ready")
        } catch (e: Throwable) { closeHardware(); throw e }
    }

    fun start() {
        check(!writerActive) { "Close the EPC writer before starting inventory" }
        check(enabled && inForeground) { "Open the Scan tab to use the trigger" }
        check(ready) { "Scanner unavailable. Close other scanner apps, then reconnect" }
        if (scanning) return
        val token = ++generation
        scanning = true
        try {
            if (mode == "barcode") {
                val reader = checkNotNull(barcode)
                reader.setDecodeCallback { entity -> barcodeResult(entity, token) }
                check(reader.startScan()) { "The barcode scan could not be started" }
                timeout = worker.schedule({
                    if (scanning && token == generation) safely {
                        stop()
                        emit(mapOf("type" to "notice", "message" to "No barcode read. Aim at a label and scan again."))
                    }
                }, 9, TimeUnit.SECONDS)
            } else {
                val reader = checkNotNull(uhf)
                reader.setInventoryCallback { tag ->
                    if (scanning && token == generation && tag != null) {
                        val value = tag.epc ?: ""
                        if (value.isNotEmpty()) collect("rfid", value, "EPC", tag.rssi)
                    }
                }
                check(reader.startInventoryTag()) { "UHF inventory could not be started" }
            }
            keepAwake(true)
            status("scanning")
        } catch (e: Throwable) {
            scanning = false
            generation++
            runCatching { barcode?.stopScan() }
            runCatching { uhf?.stopInventory() }
            status("ready")
            throw e
        }
    }

    private fun barcodeResult(entity: BarcodeEntity?, token: Int) {
        worker.execute {
            if (!scanning || mode != "barcode" || token != generation || entity == null) return@execute
            safely {
                val value = entity.barcodeData
                if (entity.resultCode == BarcodeDecoder.DECODE_SUCCESS && !value.isNullOrEmpty()) {
                    collect("barcode", value, entity.barcodeName ?: "Barcode", null)
                    stop()
                } else if (entity.resultCode == BarcodeDecoder.DECODE_ENGINE_ERROR) {
                    closeHardware()
                    error("Barcode engine error ${entity.errCode}. Reconnect the scanner")
                } else {
                    stop()
                    if (entity.resultCode != BarcodeDecoder.DECODE_CANCEL) emit(mapOf(
                        "type" to "notice", "message" to "No barcode read. Aim at a label and scan again."
                    ))
                }
            }
        }
    }

    private fun collect(kind: String, value: String, format: String, rssi: String?) {
        val now = System.currentTimeMillis()
        synchronized(pending) {
            val key = "$kind:$value"
            val item = pending[key]
            if (item == null) pending[key] = mutableMapOf(
                "kind" to kind, "value" to value, "format" to format, "rssi" to rssi,
                "count" to 1, "firstSeen" to now, "lastSeen" to now
            ) else {
                item["count"] = (item["count"] as Int) + 1
                item["lastSeen"] = now
                item["rssi"] = rssi
            }
        }
    }

    private fun flush() {
        val batch = synchronized(pending) {
            if (pending.isEmpty()) return
            pending.values.map { HashMap(it) }.also { pending.clear() }
        }
        emit(mapOf("type" to "reads", "items" to batch))
        if (mode == "rfid" && sound && SystemClock.elapsedRealtime() - lastTone > 180) {
            lastTone = SystemClock.elapsedRealtime()
            main.post {
                if (!destroyed) runCatching {
                    if (tone == null) tone = ToneGenerator(AudioManager.STREAM_MUSIC, 65)
                    tone?.startTone(ToneGenerator.TONE_PROP_BEEP, 55)
                }
            }
        }
    }

    fun stop() {
        timeout?.cancel(false)
        timeout = null
        if (!scanning) return
        var failure: Throwable? = null
        try {
            if (mode == "barcode") barcode?.stopScan()
            else check(uhf?.stopInventory() == true) { "UHF inventory did not stop. Reconnect the scanner" }
        } catch (e: Throwable) { failure = e }
        finally {
            scanning = false
            generation++
            flush()
            keepAwake(false)
        }
        if (failure != null) { closeHardware(); throw failure }
        status(if (ready) "ready" else "paused")
    }

    fun setPower(value: Int) {
        require(value in 5..30) { "Choose an RF power from 5 to 30 dBm" }
        check(mode == "rfid" && ready && !scanning) { "Connect UHF and stop inventory before changing power" }
        check(uhf?.setPower(value) == true) { "The UHF module rejected this RF power" }
        power = uhf?.power?.takeIf { it >= 0 } ?: value
        status("ready")
    }

    private fun closeHardware() {
        epcWriter.invalidate()
        timeout?.cancel(false)
        timeout = null
        if (scanning) {
            runCatching { barcode?.stopScan() }
            runCatching { uhf?.stopInventory() }
        }
        scanning = false
        generation++
        flush()
        runCatching { barcode?.setDecodeCallback(null) }
        runCatching { barcode?.close() }
        runCatching { uhf?.setInventoryCallback(null) }
        runCatching { uhf?.free() }
        barcode = null
        uhf = null
        ready = false
        power = null
        region = null
        keepAwake(false)
        status("paused")
    }

    private fun status(state: String) = emit(mapOf(
        "type" to "status", "state" to state, "mode" to mode, "ready" to ready,
        "scanning" to scanning, "power" to power, "region" to region
    ))
    private fun describe(e: Throwable): String = when (e) {
        is LinkageError -> "The Chainway SDK cannot load on this device. Use a C72 with ARM firmware."
        else -> e.message ?: "Scanner operation failed"
    }
    private fun fail(e: Throwable) { emit(mapOf("type" to "error", "message" to describe(e))) }
    private fun safely(action: () -> Unit) { try { action() } catch (e: Throwable) { fail(e) } }
    private fun emit(event: Map<String, Any?>) { main.post { if (!destroyed) sink?.success(event) } }
    private fun keepAwake(value: Boolean) {
        main.post {
            if (value && inForeground && !destroyed) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
    fun destroy() {
        inForeground = false
        enabled = false
        worker.execute {
            closeHardware()
            destroyed = true
            main.post { tone?.release(); tone = null }
            worker.shutdown()
        }
    }
}
