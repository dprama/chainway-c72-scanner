package com.example.chainway_c72_scanner

import android.os.SystemClock
import com.rscja.deviceapi.RFIDWithUHFUART
import com.rscja.deviceapi.interfaces.IUHF
import java.util.UUID

/** Called only by ChainwayScanner's serialized worker. Never uses an unfiltered write. */
class EpcWriter(
    private val getReader: () -> RFIDWithUHFUART,
    private val assertReady: () -> Unit,
    private val getGeneration: () -> Int
) {
    private data class Memory(val pc: String, val epc: String)
    private data class Target(
        val token: String, val epc: String, val pc: String, val tid: String?,
        val password: String, val generation: Int, val inspectedAt: Long
    )
    private data class Selection(val bank: Int, val bitOffset: Int, val data: String)
    private var target: Target? = null

    fun invalidate() { target = null }

    private fun hex(value: String): String {
        val compact = value.filterNot { it.isWhitespace() }.uppercase()
        return compact.removePrefix("0X")
    }

    private fun epc(value: String): String = hex(value).also {
        require(it.length in 4..124 && it.length % 4 == 0 && it.matches(Regex("[0-9A-F]+"))) {
            "Use 4–124 hexadecimal characters in complete 16-bit words"
        }
    }

    private fun password(value: String): String = hex(value).also {
        require(it.matches(Regex("[0-9A-F]{8}"))) { "Access password must contain 8 hexadecimal characters" }
    }

    class ReadFailure(sdkCode: Int) : IllegalStateException(
        "No matching tag response (SDK code $sdkCode). Use the tag's current EPC from inventory, " +
            "keep it close, and check the access password."
    )

    private fun selection(item: Target): Selection {
        // Match the PC word as well as the complete old EPC: a longer EPC sharing
        // the same prefix must not match this write operation.
        return Selection(IUHF.Bank_EPC, 16, item.pc + item.epc)
    }

    private fun readEpc(reader: RFIDWithUHFUART, pwd: String, selection: Selection, words: Int): Memory? {
        val raw = reader.readData(pwd, selection.bank, selection.bitOffset, selection.data.length * 4,
            selection.data, IUHF.Bank_EPC, 1, words + 1)?.let { hex(it) } ?: return null
        if (raw.length != (words + 1) * 4 || !raw.matches(Regex("[0-9A-F]+"))) return null
        val pc = raw.substring(0, 4)
        if (((pc.toInt(16) ushr 11) and 31) != words) return null
        return Memory(pc, raw.substring(4))
    }

    fun inspect(currentEpc: String, accessPassword: String): Map<String, Any?> {
        assertReady()
        target = null
        val old = epc(currentEpc)
        val pwd = password(accessPassword)
        val reader = getReader()
        val memory = readEpc(reader, pwd, Selection(IUHF.Bank_EPC, 32, old), old.length / 4)
            ?: throw ReadFailure(reader.errCode)
        check(memory.epc == old) {
            "The returned EPC differs from the selected EPC. Return to inventory and select the current tag."
        }
        val full = memory.pc + old
        val tid = runCatching {
            reader.readData(pwd, IUHF.Bank_EPC, 16, full.length * 4, full, IUHF.Bank_TID, 0, 6)
                ?.let { hex(it) }
                ?.takeIf { it.length == 24 && it.matches(Regex("[0-9A-F]+")) &&
                    it.any { c -> c != '0' } && it.any { c -> c != 'F' } }
        }.getOrNull()
        assertReady()
        val item = Target(UUID.randomUUID().toString(), old, memory.pc, tid, pwd,
            getGeneration(), SystemClock.elapsedRealtime())
        target = item
        return mapOf("token" to item.token, "epc" to item.epc, "tid" to item.tid)
    }

    fun write(token: String, replacement: String): Map<String, Any?> {
        assertReady()
        val item = target ?: error("Read the selected tag before writing")
        check(item.token == token && item.generation == getGeneration() &&
            SystemClock.elapsedRealtime() - item.inspectedAt <= 120_000) {
            "Tag inspection expired. Read the selected tag again"
        }
        val newEpc = epc(replacement)
        require(newEpc != item.epc) { "The new EPC must differ from the current EPC" }
        target = null // Never automatically repeat a write after an uncertain outcome.
        val reader = getReader()
        val selected = selection(item)
        val before = readEpc(reader, item.password, selected, item.epc.length / 4)
        check(before?.epc == item.epc && before.pc == item.pc) {
            "The selected tag changed or moved. Read it again before writing"
        }
        val collision = readEpc(reader, item.password, Selection(IUHF.Bank_EPC, 32, newEpc), newEpc.length / 4)
        check(collision?.epc != newEpc) { "Another tag already has this EPC. Choose a different new EPC" }
        assertReady() // Includes the Activity foreground check immediately before the write.

        var accepted = false
        var observed: String? = null
        var sdkError: Int? = null
        try {
            // This overload also adapts the EPC length in the PC word.
            accepted = reader.writeDataToEpc(item.password, selected.bank, selected.bitOffset,
                selected.data.length * 4, selected.data, newEpc)
            if (!accepted) sdkError = reader.errCode
            val verifySelection = if (item.tid != null) Selection(IUHF.Bank_TID, 0, item.tid)
                else Selection(IUHF.Bank_EPC, 32, newEpc)
            repeat(3) {
                if (observed != newEpc) {
                    SystemClock.sleep(120)
                    observed = readEpc(reader, item.password, verifySelection, newEpc.length / 4)?.epc
                }
            }
        } catch (_: Exception) {
            return outcome(item, newEpc, false, accepted, observed,
                "Write outcome is unknown. Keep the tag isolated and read its EPC before retrying.")
        }
        val verified = accepted && observed == newEpc
        val message = when {
            verified -> "EPC written and read-back verified."
            !accepted -> "The SDK did not confirm the write (code ${sdkError ?: "unknown"}). The tag may be locked, out of range, or too small. Inspect it before retrying."
            else -> "The SDK accepted the write, but read-back was not verified. Inspect the tag before retrying."
        }
        return outcome(item, newEpc, verified, accepted, observed, message)
    }

    private fun outcome(item: Target, epc: String, verified: Boolean, accepted: Boolean,
        observed: String?, message: String): Map<String, Any?> = mapOf(
        "oldEpc" to item.epc, "newEpc" to epc, "verified" to verified,
        "sdkConfirmed" to accepted, "observedEpc" to observed, "message" to message
    )
}
