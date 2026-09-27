import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Server-backed AI control plane for Alfaeq Yemen.
/// Inspired by Paperclip concepts without importing its runtime.
class AiControlPlaneService {
  static SupabaseClient get _db => SupabaseService.client;

  Future<List<Map<String, dynamic>>> listAgents() async {
    final rows = await _db.from('ai_agents').select().order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> listTasks({
    String? status,
    String? assigneeId,
  }) async {
    var query = _db.from('ai_tasks').select();
    if (status != null && status.isNotEmpty) query = query.eq('status', status);
    if (assigneeId != null && assigneeId.isNotEmpty) {
      query = query.eq('assignee_id', assigneeId);
    }
    final rows = await query.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>?> getTask(String taskId) async {
    return _db.from('ai_tasks').select().eq('id', taskId).maybeSingle();
  }

  Future<List<Map<String, dynamic>>> activity({
    String? agentId,
    String? taskId,
    int limit = 50,
  }) async {
    var query = _db.from('ai_activity_log').select();
    if (agentId != null && agentId.isNotEmpty) query = query.eq('agent_id', agentId);
    if (taskId != null && taskId.isNotEmpty) query = query.eq('task_id', taskId);
    final rows = await query.order('created_at', ascending: false).limit(limit.clamp(1, 200));
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> dashboardSnapshot() async {
    final agents = await listAgents();
    final tasks = await listTasks();
    final activeAgents = agents.where((a) => a['status'] == 'active' || a['status'] == 'running').length;
    final runningTasks = tasks.where((t) => t['status'] == 'in_progress').length;
    final blockedTasks = tasks.where((t) => t['status'] == 'blocked').length;
    final budget = agents.fold<int>(0, (sum, a) => sum + ((a['budget_monthly_cents'] as num?)?.toInt() ?? 0));
    final spend = agents.fold<int>(0, (sum, a) => sum + ((a['spend_monthly_cents'] as num?)?.toInt() ?? 0));
    return {
      'agents_total': agents.length,
      'agents_active': activeAgents,
      'tasks_total': tasks.length,
      'tasks_running': runningTasks,
      'tasks_blocked': blockedTasks,
      'budget_monthly_cents': budget,
      'spend_monthly_cents': spend,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
