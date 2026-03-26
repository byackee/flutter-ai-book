/// Cost control: daily/monthly budgets with automatic model downgrade.
/// See Chapter 10 for the full production stack.
library;

class CostController {
  final double dailyBudget;
  final double monthlyBudget;
  double _dailySpend = 0;
  double _monthlySpend = 0;
  DateTime _lastDayReset = DateTime.now();
  DateTime _lastMonthReset = DateTime.now();

  CostController({this.dailyBudget = 10.0, this.monthlyBudget = 200.0});

  bool canSpend(double estimatedCost) {
    _checkResets();
    return (_dailySpend + estimatedCost <= dailyBudget) &&
        (_monthlySpend + estimatedCost <= monthlyBudget);
  }

  void recordSpend(double cost) {
    _checkResets();
    _dailySpend += cost;
    _monthlySpend += cost;
  }

  void _checkResets() {
    final now = DateTime.now();
    if (now.day != _lastDayReset.day) {
      _dailySpend = 0;
      _lastDayReset = now;
    }
    if (now.month != _lastMonthReset.month) {
      _monthlySpend = 0;
      _lastMonthReset = now;
    }
  }

  double get dailyRemaining => dailyBudget - _dailySpend;
  double get monthlyRemaining => monthlyBudget - _monthlySpend;
}

class TokenEstimator {
  static int estimate(String text, {double charPerToken = 4.0}) {
    return (text.length / charPerToken).ceil();
  }

  static double estimateCost({
    required String input,
    required String output,
    required double inputPricePerMillion,
    required double outputPricePerMillion,
  }) {
    final inputTokens = estimate(input);
    final outputTokens = estimate(output);
    return (inputTokens * inputPricePerMillion / 1000000) +
        (outputTokens * outputPricePerMillion / 1000000);
  }
}

class ModelPricing {
  final double inputPerMillion;
  final double outputPerMillion;

  const ModelPricing(this.inputPerMillion, this.outputPerMillion);

  static const models = {
    'gpt-4o': ModelPricing(2.50, 10.00),
    'gpt-4o-mini': ModelPricing(0.15, 0.60),
    'claude-sonnet-4-20250514': ModelPricing(3.00, 15.00),
    'claude-haiku-3-20240307': ModelPricing(0.25, 1.25),
    'deepseek-chat': ModelPricing(0.14, 0.28),
  };
}
