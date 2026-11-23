import 'package:flutter/foundation.dart';

import '../data/app_store.dart';
import '../data/plans.dart';
import 'study_ai.dart';

/// tAsikaso+ plans. With accounts in use (see `StudyAi.usesAccounts`) the
/// study server holds the plan and this phone keeps a copy, so Plus
/// features still work offline; without accounts the plan lives on this
/// phone only, as before.
class PlanSync {
  PlanSync._();

  /// Switches [plan] on from now, or back to Free (null). Null when it
  /// worked, else what went wrong, in words (nothing changed then).
  static Future<String?> change(PlusPlan? plan) async {
    final store = AppStore.instance;
    if (!StudyAi.usesAccounts) {
      plan == null ? store.endPlan() : store.startPlan(plan);
      return null;
    }
    try {
      final account = await StudyAi.setTestPlan(plan);
      store.applyServerPlan(account.plan);
      return null;
    } on StudyAiException catch (e) {
      return e.message;
    }
  }

  /// The server's plan replaces this phone's copy (at start-up, after
  /// signing in, when the Plans page opens). A test plan this phone had
  /// from before accounts is carried over to the server. Returns the
  /// account, or null when accounts aren't in use or it couldn't be read.
  static Future<AccountInfo?> refresh() async {
    final store = AppStore.instance;
    try {
      var account = await StudyAi.fetchAccount();
      if (account == null) return null;
      final mine = store.subscription;
      if (account.plan == null && store.isPlus && mine != null && mine.test) {
        account = await StudyAi.setTestPlan(mine.plan);
      }
      store.applyServerPlan(account.plan);
      return account;
    } on StudyAiException catch (e) {
      debugPrint('Plan not refreshed: ${e.code} ${e.message}');
      return null;
    }
  }
}
