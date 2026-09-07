import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Production AI gateway for Alfaeq Yemen.
///
/// The model never receives unrestricted Firebase access. Database mutations,
/// payments, orders, admin actions, and developer operations must be exposed
/// later through an explicit server-side tool/permission layer.
class AlfaeqAiService {
  static const String modelName = 'gemini-3.5-flash';

  ChatSession? _chat;

  GenerativeModel _model() {
    final ai = FirebaseAI.googleAI(
      auth: FirebaseAuth.instance,
      appCheck: FirebaseAppCheck.instance,
      useLimitedUseAppCheckTokens: true,
    );

    return ai.generativeModel(
      model: modelName,
      systemInstruction: Content.system('''
أنت المساعد الذكي الرسمي لمنصة الفائق يمن.
المنصة مشروع عالمي يبدأ من اليمن ويُبنى للتوسع إلى الخليج وأفريقيا والعالم.
هدفك تقديم تجربة تتفوق على منصات الـSuper App العالمية في الذكاء، الخدمات، الأمان، السرعة، والوضوح.

قواعد أساسية:
- تحدث بالعربية افتراضياً مع دعم اللغات الأخرى عند طلبها.
- لا تدّعي تنفيذ عملية لم تُنفذ فعلياً.
- لا تطلب أو تكشف كلمات المرور أو مفاتيح API أو الرموز السرية.
- لا تنفذ طلبات مالية أو طلبات شراء أو تغييرات حساسة مباشرة من النموذج.
- أي إجراء حساس يجب أن يمر عبر طبقة صلاحيات وأدوات خادم موثوقة مع تأكيد المستخدم عند الحاجة.
- عند عدم توفر بيانات حقيقية من المنصة، صرّح بذلك بوضوح بدلاً من اختلاقها.
- صمّم إجاباتك لتكون عملية ومختصرة ومفيدة، مع احترام الخصوصية والأمن.
'''),
    );
  }

  Future<String> sendMessage(String message) async {
    final text = message.trim();
    if (text.isEmpty) return '';

    final session = _chat ??= _model().startChat(maxTurns: 40);
    final response = await session.sendMessage(Content.text(text));
    final answer = response.text?.trim();
    return answer?.isNotEmpty == true
        ? answer!
        : 'لم يصل رد نصي من خدمة الذكاء الاصطناعي.';
  }

  Stream<String> streamMessage(String message) async* {
    final text = message.trim();
    if (text.isEmpty) return;

    final session = _chat ??= _model().startChat(maxTurns: 40);
    await for (final response in session.sendMessageStream(Content.text(text))) {
      final chunk = response.text;
      if (chunk != null && chunk.isNotEmpty) yield chunk;
    }
  }

  void resetConversation() {
    _chat = null;
  }
}
