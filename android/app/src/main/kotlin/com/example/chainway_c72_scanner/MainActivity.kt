package com.example.chainway_c72_scanner

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.util.AtomicFile
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private lateinit var scanner: ChainwayScanner
    private val storage = Executors.newSingleThreadExecutor()
    private var exportResult: MethodChannel.Result? = null
    private var exportText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        scanner = ChainwayScanner(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "chainway_c72/events").setStreamHandler(scanner)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chainway_c72/methods")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> scanner.command(result) { selectMode(call.argument<String>("mode") ?: "barcode") }
                    "setEnabled" -> scanner.command(result) { enable(call.argument<Boolean>("enabled") ?: false) }
                    "beginEpcWrite" -> scanner.command(result) { beginEpcWrite() }
                    "endEpcWrite" -> scanner.command(result) { endEpcWrite() }
                    "inspectEpc" -> scanner.valueCommand(result) {
                        inspectEpc(call.argument<String>("epc") ?: "", call.argument<String>("password") ?: "")
                    }
                    "writeEpc" -> scanner.valueCommand(result) {
                        writeEpc(call.argument<String>("token") ?: "", call.argument<String>("newEpc") ?: "")
                    }
                    "start" -> scanner.command(result) { start() }
                    "stop" -> scanner.command(result) { stop() }
                    "setPower" -> scanner.command(result) { setPower(call.argument<Int>("power") ?: 20) }
                    "setSound" -> scanner.command(result) { sound = call.argument<Boolean>("enabled") ?: true }
                    "deviceInfo" -> result.success(mapOf(
                        "manufacturer" to Build.MANUFACTURER, "model" to Build.MODEL,
                        "android" to Build.VERSION.RELEASE, "sdk" to "DeviceAPI_ver20251103_release",
                        "abis" to Build.SUPPORTED_ABIS.toList()
                    ))
                    "loadState" -> storage.execute {
                        try {
                            val file = AtomicFile(File(filesDir, "scan-state.json"))
                            val text = if (file.baseFile.exists() || File(file.baseFile.path + ".bak").exists()) {
                                file.openRead().bufferedReader(Charsets.UTF_8).use { it.readText() }
                            } else null
                            runOnUiThread { result.success(text) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("STORAGE", e.message, null) }
                        }
                    }
                    "saveState" -> {
                        val text = call.argument<String>("json")
                        if (text == null) result.error("ARGUMENT", "Missing scan state", null)
                        else storage.execute {
                            val file = AtomicFile(File(filesDir, "scan-state.json"))
                            var stream: java.io.FileOutputStream? = null
                            try {
                                stream = file.startWrite()
                                stream.write(text.toByteArray(Charsets.UTF_8))
                                file.finishWrite(stream)
                                runOnUiThread { result.success(null) }
                            } catch (e: Exception) {
                                file.failWrite(stream)
                                runOnUiThread { result.error("STORAGE", e.message, null) }
                            }
                        }
                    }
                    "exportCsv" -> {
                        if (exportResult != null) result.error("BUSY", "A file export is already open", null)
                        else try {
                            exportResult = result
                            exportText = call.argument<String>("csv") ?: ""
                            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "text/csv"
                                putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "c72-scans.csv")
                            }
                            @Suppress("DEPRECATION")
                            startActivityForResult(intent, 7201)
                        } catch (e: Exception) {
                            exportResult = null
                            exportText = null
                            result.error("EXPORT", "No document picker available: ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Used by the Android document picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7201) return
        val result = exportResult ?: return
        val csv = exportText ?: ""
        exportResult = null
        exportText = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(false); return }
        storage.execute {
            try {
                val stream = contentResolver.openOutputStream(uri, "wt")
                    ?: error("The selected file could not be opened")
                stream.bufferedWriter(Charsets.UTF_8).use { it.write("\uFEFF"); it.write(csv) }
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("EXPORT", e.message, null) }
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (::scanner.isInitialized && scanner.handleTrigger(event)) return true
        return super.dispatchKeyEvent(event)
    }
    override fun onResume() {
        super.onResume()
        if (::scanner.isInitialized) scanner.foreground(true)
    }
    override fun onPause() {
        if (::scanner.isInitialized) scanner.foreground(false)
        super.onPause()
    }
    override fun onDestroy() {
        if (::scanner.isInitialized) scanner.destroy()
        exportResult?.error("CANCELLED", "Activity closed during export", null)
        exportResult = null
        storage.shutdown()
        super.onDestroy()
    }
}
