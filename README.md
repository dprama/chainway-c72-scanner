# C72 Field Scan

Flutter Android app for a Chainway C72 equipped with a barcode engine and UHF module, including selected-tag EPC writing. Uses the **official Chainway DeviceAPI_ver20251103_release.aar**, downloaded from the C72 support page. No community scanner plugin, camera decoder, or simulated hardware is used in the app.

## Install on your C72

A source checkout excludes the local `dist/` delivery files. Build the APK using the commands below and use `build/app/outputs/flutter-apk/app-release.apk`, or copy it to `dist/c72-field-scan.apk` for the installation commands here.

1. Copy `dist/c72-field-scan.apk` to the C72 and open it. Allow installation from the file manager if Android asks.
2. Close Chainway's KeyboardEmulator and other barcode/UHF demo apps so they do not compete for the scanner.
3. Open **C72 Field Scan**, select **Barcode** or **UHF RFID**, and wait for **Scanner ready**.
4. Hold a physical scan key to scan; release to stop. A barcode scan ends after one successful decode. For continuous UHF inventory, tap **Start inventory** and **Stop inventory**.
5. Open **History** to search or filter records. The export button saves matching records through Android's file picker.

The APK is a release-mode build signed with the local Android debug key for device testing. Configure a private release signing key and an application ID you own before distributing it.

## Features

- Built-in 1D/2D barcode scanning through Chainway's unified barcode API.
- Continuous UHF EPC inventory with RSSI and repeat counts.
- Separate barcode/RFID totals; identical values from different engines remain separate.
- Physical trigger handling from the key codes in Chainway's official demo.
- Foreground hardware ownership; scanners stop and close when the app is backgrounded, or when History/Settings is opened. Returning to Scan reconnects.
- Transmit power control from 5–30 dBm where supported by the module. The app reads the current power and preserves the firmware's frequency region.
- Tone feedback, full-code inspection and copy, saved history, search, filters, and CSV export.
- Version 1.0.1 releases KeyboardEmulator through the official SDK before opening UHF to prevent conflicting ownership of the reader.
- UTF-8 CSV with UTC timestamps, correct quote/newline escaping, and formula-safe text cells.
- Atomic local history storage, saved about once per second while inventory runs and again on stop/background. A sudden power loss can lose the most recent unsaved batch. Uninstalling the app clears local history.
- No account, backend, camera, internet, or broad storage permission required by the release app.

## Build

Developed with Flutter 3.44.8 / Dart 3.12.2. Use the Android SDK and JDK bundled with Android Studio (JDK 17 or newer; this machine uses 21).

```powershell
flutter pub get
flutter analyze lib test
flutter test
flutter build apk --release --target-platform android-arm,android-arm64
```

The generated APK is at `build/app/outputs/flutter-apk/app-release.apk`. It includes ARMv7 and ARM64 versions of the vendor library, for C72 models running Android 7.0+ (API 24+); validate with the exact firmware on your unit. Chainway currently documents Android 11/13 C72 variants.

With USB debugging enabled and Android Platform Tools on your PATH:

```powershell
adb devices
adb install -r dist/c72-field-scan.apk
```

If Flutter reports missing Android licenses, review and accept the needed SDK licenses using `flutter doctor --android-licenses`.

Optional rendered UI previews (synthetic test data only):

```powershell
flutter test test/preview_test.dart --dart-define=CAPTURE_PREVIEWS=true --update-goldens
```

## SDK integration

- [Official C72 SDK downloads](https://www.chainway.net/mobile/support/Info/10)
- [Official SDK archive](https://www.chainway.net/download/SDKs-Android/API_Ver20251103.rar)
- [Official barcode demo](https://www.chainway.net/download/SDKs-Android/Demo-2D_as.rar)
- [Official UHF demo](https://www.chainway.net/download/SDKs-Android/Demo-uhf_as.rar)

The AAR is bundled in `android/app/libs/`. The SDK archive, API docs and vendor demos are retained in `vendor/` on this machine and excluded from Git. SDK provenance and hashes are in `vendor/README.md`.

| Function | Official API |
| --- | --- |
| Barcode factory | `BarcodeFactory.getInstance().getBarcodeDecoder()` |
| Barcode lifecycle | `open(context)`, `setTimeOut(8)` (seconds), `close()` |
| Barcode read | `setDecodeCallback(...)`, `startScan()`, `stopScan()` |
| UHF lifecycle | `RFIDWithUHFUART.getInstance()`, `init(context)`, `free()` |
| UHF inventory | `setEPCMode()`, `setInventoryCallback(...)`, `startInventoryTag()`, `stopInventory()` |
| RF settings | `getPower()`, `setPower(...)`, `getFrequencyMode()` |

Kotlin SDK commands use one worker thread. RFID callbacks aggregate repeated EPC reads and emit batches every 80 ms over an EventChannel. SDK callback threads do not wait on Flutter. The MethodChannel handles scanner commands, local storage and document export. The UI never treats an SDK initialization failure as a successful connection.

Key files:

- `lib/main.dart`: scanner, history and settings UI.
- `lib/scan_controller.dart`: event processing, persistence and app state.
- `lib/scan_record.dart`: typed records, aggregation and CSV.
- `android/app/src/main/kotlin/com/example/chainway_c72_scanner/ChainwayScanner.kt`: official SDK integration and trigger handling.
- `android/app/src/main/kotlin/com/example/chainway_c72_scanner/MainActivity.kt`: Flutter channels, atomic files and Android document picker.

The app writes an EPC only through the explicit EPC writer flow. It does not lock, erase, kill tags, or change access passwords. Frequency-region setup is left to the C72's configuration tools.

## Validation

See `docs/VALIDATION.md` for completed automated checks and the hardware acceptance procedure. A real Android 11 C72 produced 31 unique UHF tags and 960 reads; CSV export was verified on the device. Successful barcode decoding still needs a label test.

## Write a tag EPC (version 1.1.1)

1. On **Scan**, select **UHF RFID** and inventory the tag. Stop inventory.
2. Tap the tag in Recent reads or History and choose **Write EPC**. You can also use the pencil icon in UHF mode and paste the current tag EPC.
3. Keep only the target tag close to the scanner. Confirm its **Current tag EPC** and access password (default `00000000`), then tap **Read selected tag**. This step does not write anything. Transient tag-response failures are retried up to three times, with a 200 ms pause between attempts. The current EPC must be the tag's existing value from inventory; paste the replacement into New EPC.
4. Paste the replacement hexadecimal EPC into **New EPC**, using the paste icon or Android's paste action. Spaces, line breaks, and a leading `0x` are normalized; leading zeros are retained.
5. Tap **Review EPC write**, check both values, then tap **Write EPC** to perform the write.
6. Wait for **EPC written and verified**. An SDK acknowledgement without matching read-back is reported as unverified. Inspect the tag before retrying an uncertain result.

EPCs must contain complete 16-bit words: 4, 8, 12, … up to 124 hexadecimal characters. Actual supported length depends on the tag's EPC capacity. A normal 96-bit EPC has 24 hex characters. The access password must contain exactly 8 hex characters and is never saved to history.

The native writer stops inventory, blocks scan triggers while the writer is open, and performs filtered writes only. The write filter includes the current EPC and its PC word so that a longer EPC with a matching prefix is not selected. It rechecks the selected tag immediately before writing. The official `writeDataToEpc(password, filterBank, filterPtr, filterCnt, filterData, newEpc)` API adapts the PC length. Read-back checks both the EPC payload and reported length; a readable TID prefix is used for read-back selection when available. Every attempted write consumes its inspection token; there are no automatic write retries. Earlier inventory records are kept as historical reads.

No physical tag was written while developing/testing this feature, as requested. Tag inspection can be checked without committing a write. End-to-end EEPROM writing and read-back still need a deliberate test on a target tag chosen by the operator.