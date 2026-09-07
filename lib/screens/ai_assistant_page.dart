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
  final List<_AiMessage> _messages = [
    const _AiMessage(
      text: 'مرحباً بك في ذكاء الفائق يمن. أنا المساعد الذكي للمنصة، ويمكنني مساعدتك في الخدمات والبحث والتخطيط، مع الالتزام بأن أي إجراء حساس يجب أن يمر عبر صلاحيات آمنة.',
      fromUser: false,
    ),
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
      _messages.add(_AiMessage(text: text, fromUser: true));
      _busy = true;
    });
    _scrollToEnd();

    try {
      final answer = await _ai.sendMessage(text);
      if (!mounted) return;
      setState(() => _messages.add(_AiMessage(text: answer, fromUser: false)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(_AiMessage(
        text: 'تعذر الاتصال بخدمة الذكاء الاصطناعي حالياً. تحقق من إعداد Firebase AI Logic وApp Check ثم أعد المحاولة.',
        fromUser: false,
        error: true,
      )));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollToEnd();
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ذكاء الفائق', style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(
              tooltip: 'محادثة جديدة',
              onPressed: _busy ? null : () {
                _ai.resetConversation();
                setState(() {
                  _messages
                    ..clear()
                    ..add(const _AiMessage(
                      text: 'بدأنا محادثة جديدة. كيف أساعدك داخل الفائق يمن؟',
                      fromUser: false,
                    ));
                });
              },
              icon: const Icon(Icons.add_comment_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: const Row(
                children: [
                  Icon(Icons.auto_awesome, size: 30),
                  SizedBox(width: 12),
                  Expanded(child: Text(
                    'مساعد عالمي داخل منصة واحدة — الخدمات، المعرفة، التسوق، الأعمال، والتطوير ستُبنى فوق طبقة ذكاء آمنة قابلة للتوسع.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  )),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemCount: _messages.length + (_busy ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_busy && index == _messages.length) {
                    return const _TypingBubble();
                  }
                  final message = _messages[index];
                  return _MessageBubble(message: message);
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'اسأل ذكاء الفائق...',
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
                      tooltip: 'إرسال',
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

class _AiMessage {
  final String text;
  final bool fromUser;
  final bool error;
  const _AiMessage({required this.text, required this.fromUser, this.error = false});
}

class _MessageBubble extends StatelessWidget {
  final _AiMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: message.fromUser ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: message.fromUser
              ? scheme.primary
              : (message.error ? scheme.errorContainer : scheme.surfaceContainerHighest),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.fromUser ? scheme.onPrimary : scheme.onSurface,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
