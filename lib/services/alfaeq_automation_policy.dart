/// Deterministic operator policy inspired by Jev's separation of
/// model output from business policy. The model can suggest a confidence;
/// Alfaeq policy decides whether to act, confirm, or route to a human.
enum AlfaeqDecision { act, confirm, review }

class AlfaeqAutomationPolicy {
  const AlfaeqAutomationPolicy({
    this.autoThreshold = 0.90,
    this.confirmThreshold = 0.70,
  }) : assert(confirmThreshold < autoThreshold);

  final double autoThreshold;
  final double confirmThreshold;

  AlfaeqDecision decide(double confidence, {required bool sensitive}) {
    if (sensitive) return AlfaeqDecision.review;
    if (confidence >= autoThreshold) return AlfaeqDecision.act;
    if (confidence >= confirmThreshold) return AlfaeqDecision.confirm;
    return AlfaeqDecision.review;
  }
}
