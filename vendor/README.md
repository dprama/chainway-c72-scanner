# Official Chainway SDK provenance

Downloaded on 2026-10-20 from links on https://www.chainway.net/mobile/support/Info/10.

| Artifact | Source URL | SHA-256 |
| --- | --- | --- |
| API archive | https://www.chainway.net/download/SDKs-Android/API_Ver20251103.rar | F6C4998167917CD2314D6B78649BF8B68516D7456561D6FAF79FE97BE0C75F43 |
| Barcode demo | https://www.chainway.net/download/SDKs-Android/Demo-2D_as.rar | 7FBF131A060B428551F5F75F2387F3207DA1A6143D94F1394871148F10D1E2EA |
| UHF demo | https://www.chainway.net/download/SDKs-Android/Demo-uhf_as.rar | 7773C8E4E18552E297ED6083AEE143A33D00EC84101DF795CA0637592BAD8D3B |
| Bundled DeviceAPI_ver20251103_release.aar | Extracted unchanged from API archive | 4EB338266E7ABAF3078F14FC5FB78706EFECFDC6D4783FDD3577F582FC2A2C7A |

The AAR is included unchanged under android/app/libs/. It supplies armeabi-v7a and arm64-v8a native libraries. Barcode and UHF signatures were verified with javap and the vendor Javadoc, rather than inferred from community plugins.

Local references:
- api/: original API AAR and doc.rar.
- doc/: official Javadoc from doc.rar.
- barcode/barcode-2d-demo/: official barcode sample.
- uhf/uhf-uart-demo/: official UHF sample.
- downloads/: original archives.
- sdk-internals/: extracted AAR for inspection.

These binaries and docs belong to Chainway; their applicable SDK terms continue to apply.
