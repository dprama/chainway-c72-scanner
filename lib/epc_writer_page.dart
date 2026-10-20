import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'epc_writer_controller.dart';
import 'scanner_port.dart';

class EpcWriterPage extends StatefulWidget {
  const EpcWriterPage({super.key, required this.port, this.initialEpc = ''});
  final ScannerPort port;
  final String initialEpc;
  @override
  State<EpcWriterPage> createState() => _EpcWriterPageState();
}

class _EpcWriterPageState extends State<EpcWriterPage> {
  late final EpcWriterController writer;
  late final TextEditingController current;
  final replacement = TextEditingController();
  final password = TextEditingController(text: '00000000');
  final form = GlobalKey<FormState>();
  bool showPassword = false;
  @override
  void initState() {
    super.initState();
    writer = EpcWriterController(widget.port);
    current = TextEditingController(text: widget.initialEpc);
    current.addListener(writer.invalidate);
    password.addListener(writer.invalidate);
  }

  @override
  void dispose() {
    current.removeListener(writer.invalidate);
    password.removeListener(writer.invalidate);
    current.dispose();
    replacement.dispose();
    password.dispose();
    writer.dispose();
    super.dispose();
  }

  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) return;
    replacement.text = normalizeEpcHex(data!.text!);
    setState(() {});
  }

  Future<void> inspect() async {
    FocusScope.of(context).unfocus();
    if (validateEpc(current.text) != null ||
        validateAccessPassword(password.text) != null) {
      form.currentState!.validate();
      return;
    }
    await writer.inspect(current.text, password.text);
  }

  Future<void> review() async {
    FocusScope.of(context).unfocus();
    if (!form.currentState!.validate()) return;
    final target = writer.inspection;
    if (target == null) return;
    final newEpc = normalizeEpcHex(replacement.text);
    if (newEpc == target.epc) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a different new EPC.')),
      );
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Write this EPC?'),
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Current EPC',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SelectableText(
              target.epc,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            const Text(
              'New EPC',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SelectableText(
              newEpc,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            const Text(
              'This replaces the selected tag’s EPC. Keep only the target tag near the scanner until verification finishes.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Write EPC'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) await writer.write(newEpc);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: writer,
    builder: (context, _) {
      final result = writer.result;
      return PopScope(
        canPop: !writer.busy,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Write EPC'),
            automaticallyImplyLeading: !writer.busy,
          ),
          body: SafeArea(
            child: Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  const Text(
                    'Replace a tag’s EPC',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Keep only the target tag close to the scanner. Inventory and physical scan triggers are paused on this screen.',
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: current,
                    enabled: !writer.busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLines: 3,
                    minLines: 1,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      labelText: 'Current tag EPC',
                      helperText:
                          'Use its current EPC from inventory. Paste the replacement below.',
                      helperMaxLines: 2,
                    ),
                    validator: (value) => validateEpc(value ?? ''),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: password,
                    enabled: !writer.busy,
                    obscureText: !showPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLength: 8,
                    decoration: InputDecoration(
                      labelText: 'Access password',
                      helperText:
                          'Default: 00000000. The password is not saved.',
                      suffixIcon: IconButton(
                        tooltip: showPassword
                            ? 'Hide password'
                            : 'Show password',
                        onPressed: writer.busy
                            ? null
                            : () =>
                                  setState(() => showPassword = !showPassword),
                        icon: Icon(
                          showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => validateAccessPassword(value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: writer.busy ? null : inspect,
                    icon: const Icon(Icons.search),
                    label: Text(
                      writer.busy && !writer.writing
                          ? 'Reading selected tag…'
                          : 'Read selected tag',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 52),
                    ),
                  ),
                  if (writer.inspection != null) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Tag found',
                      style: TextStyle(
                        color: Color(0xFF268664),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (writer.inspection!.tid != null)
                      SelectableText(
                        'TID: ${writer.inspection!.tid}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                  ],
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: replacement,
                    enabled: !writer.busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLines: 4,
                    minLines: 2,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: 'New EPC',
                      hintText: 'Paste hexadecimal EPC',
                      helperText:
                          '4–124 hex characters in complete 16-bit words.',
                      suffixIcon: IconButton(
                        tooltip: 'Paste new EPC',
                        onPressed: writer.busy ? null : paste,
                        icon: const Icon(Icons.content_paste),
                      ),
                    ),
                    validator: (value) => validateEpc(value ?? ''),
                  ),
                  const SizedBox(height: 20),
                  if (writer.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        writer.error!,
                        style: const TextStyle(color: Color(0xFF9A3C25)),
                      ),
                    ),
                  if (result != null && result.verified) ...[
                    const Text(
                      'EPC written and verified',
                      style: TextStyle(
                        color: Color(0xFF268664),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      result.observedEpc ?? result.newEpc,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Return to Scan to inventory the tag with its new EPC. Earlier scan history is preserved.',
                    ),
                    const SizedBox(height: 20),
                  ],
                  FilledButton.icon(
                    onPressed: writer.busy || writer.inspection == null
                        ? null
                        : review,
                    icon: writer.busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit_outlined),
                    label: Text(
                      writer.writing
                          ? 'Writing and verifying…'
                          : 'Review EPC write',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
