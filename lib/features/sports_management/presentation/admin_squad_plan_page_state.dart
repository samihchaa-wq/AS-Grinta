part of 'admin_squad_plan_page.dart';

class _AdminSquadPlanPageState extends ConsumerState<AdminSquadPlanPage> {
  List<AdminSportMatch> _matches = const [];
  String? _selectedMatchId;
  MatchConvocations? _convocations;
  MatchComposition? _composition;
  Set<String> _desiredConvoked = {};
  Set<String> _actualPresent = {};
  Map<String, int> _finishedBenchCounts = {};
  bool _postMatch = false;
  bool _compositionExisted = false;
  AvailabilityReminderSummary? _reminders;
  late _AdminStep _step;
  late final TextEditingController _limitController;
  bool _loading = true;
  bool _busy = false;
  bool _effectifDirty = false;
  String? _error;

  _AdminStep _stepFrom(String? value) {
    if (widget.showPredictionStep && value == 'prediction') {
      return _AdminStep.prediction;
    }
    if (value == 'info') return _AdminStep.info;
    if (value == 'composition') return _AdminStep.composition;
    return _AdminStep.effectif;
  }

  @override
  void initState() {
    super.initState();
    _selectedMatchId = widget.initialMatchId;
    _step = _stepFrom(widget.initialStep);
    _limitController = TextEditingController(text: '14');
    Future.microtask(_loadMatches);
  }

  @override
  void didUpdateWidget(covariant AdminSquadPlanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStep != widget.initialStep ||
        oldWidget.showPredictionStep != widget.showPredictionStep) {
      _step = _stepFrom(widget.initialStep);
    }
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  void _updateState(VoidCallback callback) => setState(callback);

  bool get _locked {
    final kickoff = _convocations?.kickoffAt;
    return kickoff != null && !DateTime.now().isBefore(kickoff);
  }

  bool get _effectifHasPendingPublication =>
      _effectifDirty || (_convocations?.hasUnpublishedChanges ?? false);

  bool get _effectifReadyForComposition =>
      _postMatch ||
      (!_effectifDirty && (_convocations?.isReadyForComposition ?? false));

  bool get _compositionLocked =>
      _busy ||
      (_postMatch
          ? _compositionExisted
          : _locked || !_effectifReadyForComposition);

  Future<void> _loadMatches() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final matches = await ref
          .read(sportWaitlistRepositoryProvider)
          .fetchUpcomingMatches();
      if (!mounted) return;
      final selected = _selectedMatchId != null &&
              matches.any((match) => match.id == _selectedMatchId)
          ? _selectedMatchId
          : (matches.isEmpty ? null : matches.first.id);
      setState(() {
        _matches = matches;
        _selectedMatchId = selected;
        _loading = false;
      });
      if (selected != null) {
        ref.invalidate(upcomingMatchFixtureProvider(selected));
        await _loadWorkspace(selected);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = humanizeError(error);
      });
    }
  }

  Future<void> _loadWorkspace(String matchId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final waitlistRepository = ref.read(sportWaitlistRepositoryProvider);
      final compositionRepository = ref.read(
        matchCompositionRepositoryProvider,
      );
      final results = await Future.wait<Object?>([
        waitlistRepository.fetchMatchConvocations(matchId),
        compositionRepository.fetchAdminComposition(matchId),
        waitlistRepository.fetchReminderSummary(matchId),
        compositionRepository.fetchFinishedBenchCounts(matchId),
      ]);
      final convocations = results[0] as MatchConvocations;
      final saved = results[1] as MatchComposition?;
      final reminders = results[2] as AvailabilityReminderSummary;
      final finishedBenchCounts = results[3] as Map<String, int>;
      final kickoffPassed = !DateTime.now().isBefore(convocations.kickoffAt);
      final finalization = kickoffPassed
          ? await ref
              .read(sportMatchFinalizationRepositoryProvider)
              .fetchAdminContext(matchId)
          : null;
      final postMatch = finalization != null &&
          finalization.isValidated &&
          (finalization.matchStatus == 'termine' ||
              finalization.matchStatus == 'archive');
      final actualPresent = <String>{
        for (final participant in finalization?.participants ?? const [])
          if (participant.present) participant.participantId,
      };
      final goalkeeperIds = postMatch
          ? const <String>{}
          : await compositionRepository.fetchGoalkeeperSeasonPlayerIds([
              for (final player in convocations.players)
                if (player.seasonPlayerId.isNotEmpty) player.seasonPlayerId,
            ]);
      final composition = postMatch
          ? _normalizePostMatchComposition(finalization, saved)
          : _normalizeComposition(convocations, saved, goalkeeperIds);
      if (!mounted || _selectedMatchId != matchId) return;
      setState(() {
        _convocations = convocations;
        _composition = composition;
        _postMatch = postMatch;
        _compositionExisted = saved != null;
        _actualPresent = actualPresent;
        _finishedBenchCounts = finishedBenchCounts;
        _reminders = reminders;
        _desiredConvoked = postMatch
            ? actualPresent
            : {
                for (final player in convocations.players)
                  if ((player.isAvailable || player.isGuest) &&
                      player.isConvoked)
                    player.participantId,
              };
        _limitController.text = '${convocations.squadSizeLimit}';
        _effectifDirty = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required Widget content,
    required String actionLabel,
    IconData? actionIcon,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: Icon(actionIcon ?? Icons.check_rounded),
                label: Text(actionLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(
        title: const SizedBox.shrink(),
        admin: true,
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading || _busy ? null : _loadMatches,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: GrintaProgressIndicator());
    if (_matches.isEmpty) {
      return const Center(
        child: GrintaEmptyState(
          icon: Icons.event_busy_rounded,
          title: 'Aucun match disponible',
          message: 'Crée un match depuis l’onglet Matchs pour préparer '
              'l’effectif et la composition.',
        ),
      );
    }
    final isInternal = _selectedMatchId == null
        ? false
        : (ref
                .watch(matchInfoProvider(_selectedMatchId!))
                .valueOrNull
                ?.isInternal ??
            false);

    return RefreshIndicator(
      onRefresh: _loadMatches,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          if (_selectedMatchId != null)
            UpcomingMatchFixtureHeader(matchId: _selectedMatchId!),
          SegmentedButton<_AdminStep>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: _AdminStep.info, label: Text('Info')),
              const ButtonSegment(
                value: _AdminStep.effectif,
                label: Text('Effectif'),
              ),
              const ButtonSegment(
                value: _AdminStep.composition,
                label: Text('Compo'),
              ),
              if (widget.showPredictionStep && !isInternal)
                const ButtonSegment(
                  value: _AdminStep.prediction,
                  label: Text('Prono'),
                ),
            ],
            selected: {_step},
            onSelectionChanged:
                _busy ? null : (value) => setState(() => _step = value.first),
          ),
          if (_busy) ...[
            const SizedBox(height: 10),
            const GrintaLinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!),
          ],
          const SizedBox(height: 16),
          if (_step == _AdminStep.info && _selectedMatchId != null)
            MatchInfoTab(matchId: _selectedMatchId!)
          else if (_step == _AdminStep.prediction && _selectedMatchId != null)
            InlineMatchPredictionCard(matchId: _selectedMatchId!)
          else if (_step == _AdminStep.composition &&
              isInternal &&
              _selectedMatchId != null)
            InternalTeamCompositionView(
              matchId: _selectedMatchId!,
              editable: true,
            )
          else if (_convocations != null && _composition != null)
            _step == _AdminStep.effectif
                ? _buildEffectif()
                : _buildComposition(),
        ],
      ),
    );
  }
}
