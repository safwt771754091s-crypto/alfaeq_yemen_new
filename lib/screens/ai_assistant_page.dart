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
  final _messages = <Map<String, Object?>>[
    {'text': 'مرحباً بك في ذكاء الفائق يمن. اطلب مني البحث أو متابعة طلبك أو إدارة سلتك أو تنفيذ خدمة داخل المنصة.', 'user': false},
  ];
  bool _busy = false;

  // One-tap entry points so the assistant feels like a super-app hub.
  static const _shortcuts = <(IconData, String, String)>[
    (Icons.search, 'ابحث عن منتج', 'ابحث عن منتج أرز في المتجر'),
    (Icons.receipt_long_outlined, 'تابع طلبي', 'ما حالة طلبي الأخير؟'),
    (Icons.shopping_cart_outlined, 'سلتي', 'ماذا يوجد في سلتي الآن؟'),
    (Icons.account_balance_wallet_outlined, 'المحفظة', 'ما رصيد محفظتي؟'),
    (Icons.storefront_outlined, 'أقرب متجر', 'ما أقرب المتاجر إليّ؟'),
    (Icons.support_agent, 'الدعم', 'أريد التواصل مع الدعم'),
  ];

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
    await _dispatch(text);
  }

  Future<void> _dispatch(String text) async {
    setState(() {
      _messages.add({'text': text, 'user': true});
      _busy = true;
    });
    _scrollToEnd();
    final answer = await _ai.sendMessage(text);
    if (!mounted) return;
    setState(() {
      _messages.add({'text': answer, 'user': false});
      _busy = false;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
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

  void _reset() {
    _ai.resetConversation();
    setState(() {
      _messages
        ..clear()
        ..add({'text': 'بدأت محادثة جديدة مع ذكاء الفائق.', 'user': false});
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ذكاء الفائق', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(onPressed: _reset, icon: const Icon(Icons.add_comment_outlined)),
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
                color: colors.primaryContainer,
              ),
              child: const Row(
                children: [
                  Icon(Icons.auto_awesome, size: 30),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'ذكاء الفائق يستخدم بيانات المنصة الحقيقية ويطلب تأكيدك قبل أي تغيير.',
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
                  final isUser = message['user'] == true;
                  return Align(
                    alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 720),
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isUser ? colors.primary : colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        (message['text'] ?? '').toString(),
                        style: TextStyle(
                          color: isUser ? colors.onPrimary : null,
                          height: 1.45,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_ai.hasPendingConfirmation)
              Card(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
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
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _shortcuts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final s = _shortcuts[i];
                  return ActionChip(
                    avatar: Icon(s.$1, size: 18),
                    label: Text(s.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: _busy ? null : () => _dispatch(s.$3),
                  );
                },
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