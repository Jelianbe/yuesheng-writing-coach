// ignore_for_file: invalid_use_of_protected_member
part of 'chat_page.dart';

extension _ChatAttitude on _ChatPageState {

  /// 切换态度：乐观更新 → persistAttitude 双写 → 失败回滚（对齐 RN setAttitude）
  Future<void> _handleAttitudeChange(AttitudeLevel attitude) async {
    if (attitude == _attitude) return;
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    final prev = _attitude;
    setState(() => _attitude = attitude);
    try {
      await ref
          .read(chatServiceProvider)
          .persistAttitude(bootstrap.sessionId, attitude);
    } catch (e) {
      setState(() => _attitude = prev);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('态度切换失败，请稍后再试')));
      }
    }
  }

  /// 批次 12 态度建议：检查是否需要建议切换档位（对齐 RN checkAttitudeSuggestion）
  ///
  /// 从消息中提取最新 diagnosis_result 的症候严重度列表作为诊断输入，
  /// 命中阈值且未在冷却期内则展示建议并记录建议时间。
  Future<void> _checkAttitudeSuggestion() async {
    if (_attitudeSuggestion != null) return; // 已有建议则跳过（对齐 RN）
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
    final messages = await sessionRepo.listMessages(bootstrap.sessionId);

    // 最新诊断消息 → 症候严重度列表（无诊断 = 空列表）
    final lastDiagnosis = messages
        .where((m) => m.messageType == 'diagnosis_result')
        .lastOrNull;
    final syndromes = <Severity>[];
    if (lastDiagnosis != null) {
      try {
        final payload =
            jsonDecode(lastDiagnosis.content) as Map<String, dynamic>;
        final rawList = (payload['syndromes'] as List?) ?? const [];
        for (final raw in rawList) {
          final sev = Severity.fromString((raw as Map)['severity'] as String?);
          if (sev != null) syndromes.add(sev);
        }
      } catch (_) {
        // 解析失败按无诊断处理，静默
      }
    }

    final suggestion = suggestAttitudeAdjustment(
      currentAttitude: _attitude,
      currentPhase: _phase,
      syndromes: syndromes,
      messageCount: messages.length,
      lastSuggestionTime: _lastSuggestionTime,
    );
    if (suggestion != null && mounted) {
      setState(() {
        _attitudeSuggestion = suggestion;
        _lastSuggestionTime = DateTime.now().millisecondsSinceEpoch;
      });
    }
  }

  /// 批次 12 态度建议：接受 → 切换到目标档位 + 关闭横幅（对齐 RN handleAcceptAttitudeSuggestion）
  Future<void> _handleAcceptAttitudeSuggestion() async {
    final suggestion = _attitudeSuggestion;
    if (suggestion == null) return;
    setState(() => _attitudeSuggestion = null);
    await _handleAttitudeChange(suggestion.targetLevel);
  }

  /// 批次 12 态度建议：暂不 → 关闭横幅（对齐 RN dismissAttitudeSuggestion）
  void _handleDismissAttitudeSuggestion() {
    if (!mounted) return;
    setState(() => _attitudeSuggestion = null);
  }

  /// 批次 12 态度建议：延迟检查（对齐 RN setTimeout(CHAT_DELAYS.ATTITUDE_CHECK_MS)）
  void _scheduleAttitudeCheck() {
    Future.delayed(const Duration(milliseconds: 500), _checkAttitudeSuggestion);
  }

  /// 加载已持久化的态度 + 阶段（bootstrap 完成后调用）
  /// loadAttitudeState 返回 (attitude, phase)，一并刷新头部状态区
  Future<void> _loadAttitude(String sessionId) async {
    try {
      final state = await ref
          .read(chatServiceProvider)
          .loadAttitudeState(sessionId);
      if (mounted) {
        setState(() {
          _attitude = state.attitude;
          _phase = state.phase;
        });
        // 批次 18：P2 阶段进入时加载活跃问题（对齐 RN useEffect currentPhase 依赖）
        if (state.phase == TeachingPhase.p2PracticeLoop) {
          _loadActiveProblems(sessionId);
        }
      }
    } catch (_) {
      // 加载失败保持默认档位，静默（release 不暴露技术细节）
    }
  }

  /// 加载当前 P2 子阶段（ChatHeader 更多菜单展示用）
  Future<void> _loadSubphase(String sessionId) async {
    try {
      final subphase = await ref
          .read(chatServiceProvider)
          .loadSubphase(sessionId);
      if (mounted) {
        setState(() => _subphase = subphase);
      }
    } catch (_) {
      // 加载失败保持 null，静默
    }
  }
}
