import 'package:flutter/material.dart';

import '../services/follow_service.dart';

/// WeChat-style follow button (متابعة / متابَع). Optimistic toggle with a
/// graceful no-op when the user is signed out.
class FollowButton extends StatefulWidget {
  const FollowButton({
    super.key,
    required this.targetType,
    required this.targetId,
    this.compact = false,
    this.onChanged,
  });

  final String targetType; // 'store' | 'user'
  final String targetId;
  final bool compact;
  final ValueChanged<bool>? onChanged;

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  bool _following = false;
  int _count = 0;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await FollowService().state(targetType: widget.targetType, targetId: widget.targetId);
      if (!mounted) return;
      setState(() {
        _following = s.following;
        _count = s.followerCount;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    final before = _following;
    setState(() {
      _following = !before;
      _count += before ? -1 : 1;
    });
    try {
      final now = await FollowService().toggle(targetType: widget.targetType, targetId: widget.targetId);
      if (!mounted) return;
      setState(() {
        _following = now;
        _busy = false;
      });
      widget.onChanged?.call(now);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _following = before;
        _count += before ? 1 : -1;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر تحديث المتابعة، حاول مرة أخرى')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 32,
        width: 32,
        child: Center(child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    final label = _following ? 'متابَع' : 'متابعة';
    return OutlinedButton.icon(
      onPressed: _busy ? null : _toggle,
      icon: Icon(_following ? Icons.check : Icons.add, size: widget.compact ? 16 : 18),
      label: Text(
        widget.compact || _count == 0 ? label : '$label · $_count',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: widget.compact ? 12 : 14),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _following ? Colors.grey.shade700 : const Color(0xFF0D6EFD),
        side: BorderSide(color: _following ? Colors.grey.shade400 : const Color(0xFF0D6EFD)),
        padding: EdgeInsets.symmetric(horizontal: widget.compact ? 10 : 16, vertical: widget.compact ? 4 : 8),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
