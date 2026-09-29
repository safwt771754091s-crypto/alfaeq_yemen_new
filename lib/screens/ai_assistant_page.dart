import 'package:flutter/material.dart';
import '../ai/ai_service.dart';

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});
  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _ai = AlfaeqAiService();
  final List<Map<String, Object?>> _messages = [
    {'text': 'مرحباً بك في ذكاء الفائق يمن. اطلب مني البحث، متابعة طلبك، إدارة سلتك أو تنفيذ خدمة داخل المنصة.', 'user': false},
  ];
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _messages.add({'text': text, 'user': true});
      _busy = true;
    });
    final answer = await _ai.sendMessage(text);
    if (!mounted) return;
    setState(() {
      _messages.add({'text': answer, 'user': false});
      _busy = false;
    });
  }

  Future<void> _confirm() async {
    if (_busy || !_ai.hasPendingConfirmation) return;
    setState(() => _busy = true);
    final answer = await _ai.confirmPendingAction();
    if (!mounted) return;
    setState(() {
      _messages.add({'text': answer, 'user': false});
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ذكاء الفائق', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(
              onPressed: () => setState(_ai.resetConversation),
              icon: const Icon(Icons.add_comment_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: scheme.primaryContainer,
              ),
              child: const Row(
                children: [
                  Icon(Icons.auto_awesome, size: 30),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'ذكاء الفائق يستخدم بيانات المنصة الحقيقية، ويطلب التأكيد قبل أي تغيير.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length + (_busy ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_busy && index == _messages.length) {
                    return const Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  final message = _messages[index];
                  final user = message['user'] == true;
                  return Align(
                    alignment: user ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 720),
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: user ? scheme.primary : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        (message['text'] ?? '').toString(),
                        style: TextStyle(
                          color: user ? scheme.onPrimary : null,
                          height: 1.45,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_ai.hasPendingConfirmation)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('مراجعة وتأكيد العملية', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        Text(_ai.pendingActionDescription),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _busy ? null : _confirm,
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('تأكيد التنفيذ'),
                        ),
                        OutlinedButton(
                          onPressed: _busy ? null : () => setState(_ai.cancelPendingAction),
                          child: const Text('إلغاء'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'اطلب من ذكاء الفائق...',
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _busy ? null : _send,
                      icon: const Icon(Icons.arrow_upward),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
