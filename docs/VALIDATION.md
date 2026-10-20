# Validation

## Automated checks

- Flutter static analysis.
- Record aggregation, timestamps, leading-zero identifiers, separate engine identities, repeat counts, search/filtering, persistence round-trips, malformed history protection, CSV escaping, export ordering and scanner failure behavior.
- Compact-screen widget flows: barcode, RFID inventory, history and settings.
- Larger-text layout at 320 × 640 logical pixels.
- Native Android compilation against the downloaded official Chainway AAR.
- Optional UI renders use synthetic readings and a fake scanner transport confined to tests.

## Required on a real C72

The initial build was verified without hardware. Follow-up testing used a real C72 on Android 11; see the device results below. Complete any outstanding checks on your device before operational use:

1. Close KeyboardEmulator and other scanner apps. Install and launch the APK.
2. In Barcode mode, confirm **Scanner ready**. Read Code128, EAN/UPC and QR labels using both the screen button and physical trigger. Verify the exact decoded values, symbology and timeout behavior.
3. Read a label with leading zeros, then repeat it. Confirm one unique code and an incrementing read count.
4. Select UHF RFID. Confirm ready, current power, and several EPC tags. Check that unique totals, repeated reads and RSSI update while moving tags.
5. Hold and release each physical trigger. Verify scanning stops on release. Start screen-controlled inventory and stop it with the screen button.
6. Stop UHF inventory and adjust power. Confirm the requested value is accepted or that a clear error appears. Check the device's RF region in its configuration tools.
7. Start scanning and background the app, lock the screen, switch between scanner modes and open History/Settings. Verify the light/RF inventory stops and reconnects when returning.
8. Export a filtered CSV to Downloads. Check timestamps and counts; cancel an export and confirm normal operation resumes.
9. Close and relaunch the app. Verify history and sound preference restore.
10. Clear history using the confirmation dialog and confirm both barcode and RFID records are removed.
11. Run an inventory at the expected tag volume for several minutes and verify responsiveness, counts, battery use and stable reconnection.

If initialization fails, verify that both modules are fitted to this C72, close competing scanner services and retry. Firmware-specific trigger routing or scanner-service behavior may require adjustments after this device test.

## Results on 2026-10-20

- `flutter analyze lib test`: no issues.
- `flutter test --reporter expanded`: 13 passed; the optional preview test is skipped in this run.
- Optional preview render: 1 passed; barcode, RFID and history images reviewed under `docs/previews/`.
- Android debug and release APK compilation succeeded against the unchanged vendor AAR.
- The initial build had no Android device connected. A real C72 was connected for the follow-up checks below.

## C72 device follow-up on 2026-10-20

- Installed and launched successfully on a C72 running Android 11, with ARM64 and ARMv7 support.
- Barcode SDK opened and scan commands reached the Zebra engine. A scan timed out normally. Successful barcode decoding remains untested because no label was available.
- Found a UHF ownership conflict: the background KeyboardEmulator helper held the reader. The installed official UHF demo failed with the same serial handshake error while that helper was running.
- Stopping the competing helper restored UHF access immediately at the existing 20 dBm transmit power.
- Live inventory collected 31 unique EPC tags and 960 reads, with RSSI. Screen-controlled stop returned the scanner to ready.
- History showed all 31 real RFID records.
- Android document-picker export saved a CSV into Downloads. The exported file contained 31 RFID rows totaling 960 reads and valid UTC timestamps.
- Version 1.0.1 adds the official SDK call `BarcodeUtility.closeKeyboardHelper(context)` before direct UHF initialization, followed by a short wait for asynchronous hardware release.
- Raw device screenshots, hierarchy dumps, and the real CSV stay in `docs/device-test/` and are excluded from the portable source archive.
### Patched app confirmation

- Version 1.0.1 (build 2) installed on the C72; the 31-tag/960-read history survived the update.
- Barcode-to-UHF switching reconnected successfully using the SDK helper-release fix, without another ADB force-stop.
- A fresh inventory in the patched app increased the saved totals to 33 unique tags and 1,070 reads. The app was left in UHF mode, stopped and ready at 20 dBm.
- Actual physical trigger presses and successful barcode decoding remain user-operated acceptance checks. No barcode label was available during this test.

## EPC writer feature (1.1.0)

- Added selected-tag EPC inspection, a paste-friendly replacement EPC field, access-password input, and explicit old/new EPC review.
- Native SDK writes always use a nonempty current-PC/current-EPC filter. EPC length is updated by the official SDK helper.
- Inventory and physical scan triggers are blocked while the writer is open. Inspection expires on hardware reconnection/backgrounding and after two minutes.
- Write acknowledgement and read-back verification are separate outcomes. There are no automatic write retries.
- `flutter analyze lib test`: clean. `flutter test --reporter expanded`: 21 passed, optional preview test skipped.
- Automated write tests use only a fake transport. The human requested feature-only delivery; no physical EPC write is authorized or performed.

- Version 1.1.0 (build 3) installed successfully on the connected Android 11 C72; existing scan history was retained. The EPC writer opened and its read-only inspection found the selected tag and read its EPC and TID. No physical write was submitted.

## EPC read reliability follow-up (1.1.1)

- Observed the selected-tag read failure on the connected C72. The SDK logged readData error 65535 while UHF initialization succeeded. A read-only retry of the unchanged current EPC then succeeded and returned its TID; this does not establish the earlier KeyboardEmulator ownership conflict as the cause.
- Added at most three read-only inspection attempts, only for tag-response failures. Other errors and write requests are not retried. Backgrounding, changing the target, or disposal cancels pending retries and discards late inspection results.
- The failure message includes the SDK code and guidance to use the current EPC from inventory. The replacement EPC remains a separate input.

- Static analysis is clean; 26 Flutter tests passed (optional preview test skipped). The Android release APK compiled against the official Chainway AAR.
- Version 1.1.1 (build 4) installed on the connected C72. A synthetic unmatched EPC produced exactly three readData failures and the intended no-match guidance. The vendor log showed 65535 while the SDK error getter reported 34.
- Restored the original selected EPC and verified Tag found with its TID on the updated app. Existing history remained intact. A brief USB transport disconnect interrupted a UI capture; the device reconnected and the successful read was confirmed in both the screenshot and UI hierarchy. No write was submitted and the replacement field remained empty.
