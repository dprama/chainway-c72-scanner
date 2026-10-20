import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'scan_controller.dart';
import 'scan_record.dart';
import 'scanner_port.dart';
import 'epc_writer_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FieldScanApp(controller: ScanController(AndroidScannerPort())));
}

const ink = Color(0xFF142B40);
const blue = Color(0xFF1268BC);
const paper = Color(0xFFF2F5F8);
const muted = Color(0xFF5C6F7E);
const line = Color(0xFFD9E2EA);
const amber = Color(0xFFE6923A);

class FieldScanApp extends StatelessWidget {
  const FieldScanApp({super.key, required this.controller});
  final ScanController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'C72 Field Scan',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(seedColor: blue, surface: Colors.white),
      fontFamily: 'sans-serif',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontFamily: 'sans-serif-condensed',
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: ink),
        bodyMedium: TextStyle(fontSize: 14, color: ink),
        bodySmall: TextStyle(fontSize: 12, color: muted),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Color(0xFFE5EFF8),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    home: FieldScanHome(controller: controller),
  );
}

class FieldScanHome extends StatefulWidget {
  const FieldScanHome({super.key, required this.controller});
  final ScanController controller;
  @override
  State<FieldScanHome> createState() => _FieldScanHomeState();
}

class _FieldScanHomeState extends State<FieldScanHome> {
  ScanController get c => widget.controller;
  String query = '';
  ScanKind? filter;
  @override
  void initState() {
    super.initState();
    unawaited(c.initialize());
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> export() async {
    final text = await c.export(
      filter: c.tab == 1 ? filter : c.kind,
      query: c.tab == 1 ? query : '',
    );
    if (text != null) message(text);
  }

  Future<void> clear() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear saved history?'),
        content: const Text(
          'This removes all barcode and RFID records from this app. Export a CSV first if you need to keep them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep history'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (approved == true) await c.clearHistory();
  }

  Future<void> openEpcWriter([String? target]) async {
    if (c.busy || c.exporting || c.loading) return;
    if (c.tab != 0) await c.changeTab(0);
    if (c.kind != ScanKind.rfid) await c.changeMode(ScanKind.rfid);
    if (!await c.beginEpcWriter()) return;
    if (!mounted) {
      await c.endEpcWriter();
      return;
    }
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => EpcWriterPage(
            port: c.port,
            initialEpc: target ?? c.latest?.value ?? '',
          ),
        ),
      );
    } finally {
      await c.endEpcWriter();
    }
  }

  Future<void> adjustPower() async {
    var selected = (c.power ?? 20).clamp(5, 30).toDouble();
    final power = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              8,
              24,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UHF transmit power',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Lower power reads closer tags. Higher power increases the reading range.',
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    '${selected.round()} dBm',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                Slider(
                  value: selected,
                  min: 5,
                  max: 30,
                  divisions: 25,
                  label: '${selected.round()} dBm',
                  onChanged: (value) => update(() => selected = value),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text('5 dBm'), Text('30 dBm')],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, selected.round()),
                    child: const Text('Apply power'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (power != null) await c.setPower(power);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      return Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.document_scanner_outlined,
                  color: Colors.white,
                  size: 23,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FIELD SCAN',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'CHAINWAY C72',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.6,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            if (c.tab == 0 && c.kind == ScanKind.rfid)
              IconButton(
                tooltip: 'Write EPC',
                onPressed: c.ready && !c.busy && !c.exporting
                    ? openEpcWriter
                    : null,
                icon: const Icon(Icons.edit_note_outlined),
              ),
            if (c.tab != 2)
              IconButton(
                tooltip: 'Export CSV',
                onPressed:
                    c.loading || c.exporting || c.busy || c.recordCount == 0
                    ? null
                    : export,
                icon: c.exporting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_download_outlined),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (c.error != null)
                _ErrorPanel(
                  text: c.error!,
                  onRetry: c.busy || c.storageBlocked ? null : c.reconnect,
                  onDismiss: c.storageBlocked ? null : c.dismissError,
                ),
              if (c.loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Expanded(
                  child: switch (c.tab) {
                    0 => scanView(context),
                    1 => historyView(context),
                    _ => settingsView(context),
                  },
                ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: c.tab,
          onDestinationSelected: c.busy || c.loading || c.exporting
              ? null
              : c.changeTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.qr_code_scanner),
              label: 'Scan',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              label: 'History',
            ),
            NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
          ],
        ),
      );
    },
  );

  Widget scanView(BuildContext context) {
    final rfid = c.kind == ScanKind.rfid;
    final reads = c.recent();
    final latest = c.latest;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            children: [
              SegmentedButton<ScanKind>(
                showSelectedIcon: false,
                expandedInsets: EdgeInsets.zero,
                segments: const [
                  ButtonSegment(
                    value: ScanKind.barcode,
                    icon: Icon(Icons.qr_code_2),
                    label: Text('Barcode'),
                  ),
                  ButtonSegment(
                    value: ScanKind.rfid,
                    icon: Icon(Icons.sensors),
                    label: Text('UHF RFID'),
                  ),
                ],
                selected: {c.kind},
                onSelectionChanged: c.busy || c.storageBlocked || c.exporting
                    ? null
                    : (values) => c.changeMode(values.first),
                style: ButtonStyle(
                  minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _StatusDot(ready: c.ready, scanning: c.scanning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.busy || c.state == 'opening'
                          ? 'Connecting scanner…'
                          : c.scanning
                          ? (rfid ? 'Inventory running' : 'Reading barcode…')
                          : c.ready
                          ? 'Scanner ready'
                          : 'Scanner disconnected',
                      style: const TextStyle(
                        color: muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (rfid && c.ready)
                    TextButton(
                      onPressed: c.scanning || c.busy ? null : adjustPower,
                      child: Text(
                        c.power == null ? 'RF power' : '${c.power} dBm',
                      ),
                    ),
                  if (!c.ready && !c.busy && !c.storageBlocked)
                    TextButton(
                      onPressed: c.reconnect,
                      child: const Text('Connect'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Semantics(
                label: latest == null
                    ? 'Waiting for a scan'
                    : 'Latest scan: ${latest.value}',
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: latest == null
                        ? null
                        : () => showRecord(context, latest),
                    child: CustomPaint(
                      foregroundPainter: _ScanCorners(active: c.scanning),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 160),
                        padding: const EdgeInsets.all(24),
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  rfid ? Icons.sensors : Icons.qr_code_2,
                                  color: blue,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    latest == null
                                        ? (rfid
                                              ? 'UHF INVENTORY'
                                              : 'BARCODE CAPTURE')
                                        : 'LAST READ',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: muted,
                                      letterSpacing: 1.4,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (latest != null)
                                  const Icon(
                                    Icons.open_in_full,
                                    size: 15,
                                    color: muted,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              latest?.value ??
                                  (rfid
                                      ? 'Find nearby tags.'
                                      : 'Ready for the next label.'),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: latest == null
                                    ? 'sans-serif-condensed'
                                    : 'monospace',
                                fontSize: latest == null ? 25 : 19,
                                fontWeight: FontWeight.w600,
                                color: ink,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              latest == null
                                  ? (rfid
                                        ? 'Hold the trigger or tap Start inventory.'
                                        : 'Aim the scanner and hold the trigger.')
                                  : '${latest.format}  ·  ${clock(latest.lastSeen)}${latest.rssi == null ? '' : '  ·  ${latest.rssi} dBm'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: line),
                    bottom: BorderSide(color: line),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        value: c.unique(c.kind),
                        label: rfid ? 'Unique tags' : 'Unique codes',
                      ),
                    ),
                    Container(width: 1, height: 38, color: line),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: _Metric(
                          value: c.total(c.kind),
                          label: 'Total reads',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (c.notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(c.notice!, style: const TextStyle(color: muted)),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Recent reads',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: c.busy ? null : () => c.changeTab(1),
                    child: const Text('View history'),
                  ),
                ],
              ),
              if (reads.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Scanned codes appear here and are saved on this device.',
                    style: TextStyle(color: muted),
                  ),
                ),
              for (final record in reads)
                _RecordRow(
                  record: record,
                  onTap: () => showRecord(context, record),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: c.busy || !c.ready || c.storageBlocked || c.exporting
                  ? null
                  : c.toggleScan,
              icon: c.busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      c.scanning
                          ? Icons.stop_rounded
                          : rfid
                          ? Icons.sensors
                          : Icons.qr_code_scanner,
                    ),
              label: Text(
                c.scanning
                    ? (rfid ? 'Stop inventory' : 'Stop scan')
                    : rfid
                    ? 'Start inventory'
                    : 'Scan barcode',
              ),
              style: c.scanning
                  ? FilledButton.styleFrom(backgroundColor: blue)
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget historyView(BuildContext context) {
    final records = c.history(query: query, filter: filter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Scan history',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Clear all history',
                    onPressed:
                        c.busy || (c.recordCount == 0 && !c.storageBlocked)
                        ? null
                        : clear,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search code or format',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => query = value),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: filter == null,
                    onSelected: (_) => setState(() => filter = null),
                  ),
                  ChoiceChip(
                    label: const Text('Barcodes'),
                    selected: filter == ScanKind.barcode,
                    onSelected: (_) =>
                        setState(() => filter = ScanKind.barcode),
                  ),
                  ChoiceChip(
                    label: const Text('RFID'),
                    selected: filter == ScanKind.rfid,
                    onSelected: (_) => setState(() => filter = ScanKind.rfid),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${records.length} unique records · saved on this device',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: records.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No matching records.\nScan a barcode or a UHF tag to get started.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  itemCount: records.length,
                  itemBuilder: (context, index) => _RecordRow(
                    record: records[index],
                    onTap: () => showRecord(context, records[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget settingsView(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Scanner settings',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 20),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Read feedback'),
        subtitle: const Text('Play a short tone when codes are read.'),
        value: c.sound,
        onChanged: c.busy ? null : c.setSound,
      ),
      const Divider(color: line),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.touch_app_outlined, color: blue),
        title: Text('Use the physical trigger'),
        subtitle: Text(
          'Hold to read; release to stop. For continuous UHF inventory, use the on-screen Start and Stop buttons.',
        ),
      ),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.sensors, color: blue),
        title: Text('UHF range'),
        subtitle: Text(
          'Select UHF RFID on the Scan tab, then tap the dBm value to adjust transmit power. The device’s configured frequency region is preserved.',
        ),
      ),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.save_outlined, color: blue),
        title: Text('Saved locally'),
        subtitle: Text(
          'History includes repeat counts and first/last read times. Use Export CSV to save a file. Uninstalling this app removes its local history.',
        ),
      ),
      const Divider(color: line),
      const SizedBox(height: 12),
      Text('Device', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      _InfoRow(
        label: 'Model',
        value:
            '${c.device['manufacturer'] ?? 'Chainway'} ${c.device['model'] ?? 'C72'}',
      ),
      _InfoRow(
        label: 'Android',
        value: '${c.device['android'] ?? 'Unavailable'}',
      ),
      const _InfoRow(label: 'SDK', value: 'Chainway DeviceAPI\n2025-11-03'),
      const SizedBox(height: 20),
      const Text(
        'If the scanner cannot connect, close KeyboardEmulator and other barcode or UHF demo apps, then return to Scan and tap Connect.',
        style: TextStyle(color: muted, height: 1.5),
      ),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: c.busy || (c.recordCount == 0 && !c.storageBlocked)
            ? null
            : clear,
        icon: const Icon(Icons.delete_outline),
        label: const Text('Clear all history'),
      ),
      const SizedBox(height: 12),
      const Center(
        child: Text(
          'C72 Field Scan · 1.1.1',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ),
    ],
  );

  Future<void> showRecord(
    BuildContext context,
    ScanRecord record,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              record.kind == ScanKind.rfid ? 'RFID tag' : 'Barcode',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            SelectableText(
              record.value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 20,
                color: ink,
              ),
            ),
            const SizedBox(height: 20),
            if (record.kind == ScanKind.rfid)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    openEpcWriter(record.value);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Write EPC'),
                ),
              ),
            _InfoRow(label: 'Format', value: record.format),
            _InfoRow(label: 'Read count', value: '${record.count}'),
            if (record.rssi != null)
              _InfoRow(label: 'Last RSSI', value: '${record.rssi} dBm'),
            _InfoRow(label: 'First read', value: dateTime(record.firstSeen)),
            _InfoRow(label: 'Last read', value: dateTime(record.lastSeen)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: record.value));
                  message('Code copied');
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy code'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
String dateTime(DateTime time) =>
    '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}  ${clock(time)}';

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final int value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$value',
        style: const TextStyle(
          fontFamily: 'sans-serif-condensed',
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
      Text(label, style: const TextStyle(fontSize: 12, color: muted)),
    ],
  );
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.ready, required this.scanning});
  final bool ready;
  final bool scanning;
  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: scanning
          ? blue
          : ready
          ? const Color(0xFF268664)
          : muted,
    ),
  );
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, required this.onTap});
  final ScanRecord record;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(
        record.kind == ScanKind.rfid ? Icons.sensors : Icons.qr_code_2,
        color: blue,
      ),
      title: Text(
        record.value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
      subtitle: Text(
        '${record.format} · ${clock(record.lastSeen)}${record.rssi == null ? '' : ' · ${record.rssi} dBm'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: muted, fontSize: 11),
      ),
      trailing: Text(
        '×${record.count}',
        style: const TextStyle(fontWeight: FontWeight.w700, color: ink),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.text, this.onRetry, this.onDismiss});
  final String text;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: const Color(0xFFFFEDE7),
    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.error_outline, color: Color(0xFF9A3C25), size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: const TextStyle(fontSize: 13, color: Color(0xFF7E311D)),
              ),
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: const Text('Reconnect')),
            ],
          ),
        ),
        if (onDismiss != null)
          IconButton(
            tooltip: 'Dismiss error',
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18),
          ),
      ],
    ),
  );
}

class _ScanCorners extends CustomPainter {
  const _ScanCorners({required this.active});
  final bool active;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = active ? blue : amber
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    const d = 12.0;
    const k = 9.0;
    for (final corner in [
      [const Offset(k, k + d), const Offset(k, k), const Offset(k + d, k)],
      [
        Offset(size.width - k - d, k),
        Offset(size.width - k, k),
        Offset(size.width - k, k + d),
      ],
      [
        Offset(k, size.height - k - d),
        Offset(k, size.height - k),
        Offset(k + d, size.height - k),
      ],
      [
        Offset(size.width - k - d, size.height - k),
        Offset(size.width - k, size.height - k),
        Offset(size.width - k, size.height - k - d),
      ],
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(corner[0].dx, corner[0].dy)
          ..lineTo(corner[1].dx, corner[1].dy)
          ..lineTo(corner[2].dx, corner[2].dy),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_ScanCorners oldDelegate) => oldDelegate.active != active;
}
