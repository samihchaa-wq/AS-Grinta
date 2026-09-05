part of 'admin_squad_plan_page.dart';

class _AdminSquadPlanPageState extends ConsumerState<AdminSquadPlanPage> {
  List<AdminSportMatch> _matches = const [];
  String? _selectedMatchId;
  MatchConvocations? _convocations;
  MatchComposition? _composition;
  Map<String, ConvocationStatus> _desiredEffectifStatuses = {};
  Set<String> _goalkeeperIds = {};
  Set<String> _actualPresent = {};
  Map<String, int> _finishedBenchCounts = {};
  Map<String, String> _canonicalPlayerIds = {};
  Map<String, PlayerPositionProfile> _positionProfiles =
      kPlayerPositionProfiles;
  bool _postMatch = false;
  bool _compositionExisted = false;
  AvailabilityReminderSummary? _reminders;
  late _AdminStep _step;
  late final TextEditingController _limitController;
  Timer? _effectifAutosave;
  bool _effectifSaving = false;

  /// Compteur des décisions prises à l'écran.
  ///
  /// Il distingue une réponse du serveur encore d'actualité d'une réponse
  /// doublée par un nouveau geste pendant l'aller-retour : dans ce cas les
  /// décisions affichées restent celles de l'admin, et c'est l'écriture
  /// suivante qui les portera.
  int _effectifRevision = 0;
  bool _compositionDirty = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  _AdminStep _stepFrom(String? value) {
    if (widget.showPredictionStep && value == 'prediction') {
      return _AdminStep.prediction;
    }
    if (value == 'info') return _AdminStep.info;
    if (value == 'composition') return _AdminStep.composition;
    if (value == 'live') return _AdminStep.live;
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
    // Seule une nouvelle demande explicite (une autre section dans l'URL)
    // change l'onglet affiché. showPredictionStep, lui, bascule tout seul à
    // T-15 quand les pronostics ferment : le prendre pour une demande de
    // navigation renvoyait le coach sur l'onglet d'arrivée — typiquement Info —
    // en plein Tableau Blanc, dès le premier rafraîchissement suivant.
    if (oldWidget.initialStep != widget.initialStep) {
      _step = _stepFrom(widget.initialStep);
      return;
    }
    // L'onglet Prono disparaît à T-15 : s'il était affiché, il faut bien
    // reprendre la main, mais uniquement dans ce cas-là.
    if (!widget.showPredictionStep && _step == _AdminStep.prediction) {
      _step = _stepFrom(widget.initialStep);
    }
  }

  void _clearEffectifTapSelection() {
    if (_EffectifTapSelection.selectedFor(
          owner: this,
          matchId: _selectedMatchId,
        ) !=
        null) {
      _EffectifTapSelection.clear();
    }
  }

  @override
  void dispose() {
    _effectifAutosave?.cancel();
    _clearEffectifTapSelection();
    _limitController.dispose();
    super.dispose();
  }

  void _updateState(VoidCallback callback) => setState(callback);

  bool get _locked {
    final kickoff = _convocations?.kickoffAt;
    return kickoff != null && isMatchAdminEditLocked(kickoff);
  }

  /// L'effectif du match existe-t-il déjà côté serveur ?
  ///
  /// Ce n'est plus une étape que l'admin doit franchir : l'écran l'écrit
  /// lui-même. La composition ne s'appuie dessus que pour sa publication.
  bool get _effectifWritten => _convocations?.isPublished ?? false;

  bool get _canSaveEffectifNow => canSaveEffectifNow(
        busy: _busy,
        locked: _locked,
        postMatch: _postMatch,
        saving: _effectifSaving,
      );

  bool get _compositionLocked => _busy || (!_postMatch && _locked);

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
      if (selected != _selectedMatchId) {
        _clearEffectifTapSelection();
      }
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
      final seasonPlayerIds = [
        for (final player in convocations.players)
          if (player.seasonPlayerId.isNotEmpty) player.seasonPlayerId,
      ];
      final goalkeeperIds = postMatch
          ? const <String>{}
          : await compositionRepository.fetchGoalkeeperSeasonPlayerIds(
              seasonPlayerIds,
            );
      final canonicalPlayerIds = postMatch
          ? const <String, String>{}
          : await compositionRepository.fetchCanonicalPlayerIds(
              seasonPlayerIds,
            );
      var positionProfiles = kPlayerPositionProfiles;
      if (!postMatch) {
        final archive = await ref.read(playerPositionArchiveProvider.future);
        positionProfiles = archive;
        try {
          positionProfiles = mergePlayerPositionProfiles(
            history: await compositionRepository.fetchPlayerPositionHistory(
              kLivePositionHistoryStart,
            ),
            archive: archive,
          );
        } catch (_) {
          positionProfiles = archive;
        }
      }
      // Une composition déjà enregistrée est la source de vérité, y compris
      // après le match. La finalisation sert à créer une composition seulement
      // lorsqu'il n'en existe pas encore ; elle ne doit jamais reconstruire ou
      // filtrer une feuille historique au simple chargement de l'éditeur.
      final composition = postMatch
          ? saved != null
              ? _preserveSavedLayout(saved)
              : _normalizePostMatchComposition(finalization, null)
          : _normalizeComposition(convocations, saved, goalkeeperIds);
      if (!mounted || _selectedMatchId != matchId) return;
      setState(() {
        _convocations = convocations;
        _composition = composition;
        _postMatch = postMatch;
        _compositionExisted = saved != null;
        _actualPresent = actualPresent;
        _finishedBenchCounts = finishedBenchCounts;
        _canonicalPlayerIds = canonicalPlayerIds;
        _goalkeeperIds = goalkeeperIds;
        _positionProfiles = positionProfiles;
        _reminders = reminders;
        _desiredEffectifStatuses = _effectifStatusesFor(
          convocations: convocations,
          postMatch: postMatch,
          actualPresent: actualPresent,
        );
        _limitController.text = '${convocations.squadSizeLimit}';
        _compositionDirty = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // Un match dont l'effectif n'a jamais été écrit reste impubliable côté
    // serveur. On l'écrit ici, une fois le chargement terminé, avec les
    // convocations que le serveur a déjà calculées : plus rien à valider à la
    // main avant de poser la composition.
    if (mounted &&
        _selectedMatchId == matchId &&
        _convocations?.matchId == matchId &&
        needsInitialEffectifWrite(
          convocationPublished: _effectifWritten,
          busy: _busy,
          locked: _locked,
          postMatch: _postMatch,
        )) {
      // Sans ce garde-fou, un refus du serveur relancerait un chargement, qui
      // relancerait l'écriture : l'écran tournerait en rond.
      await _persistEffectif(recoverOnError: false);
    }
  }

  /// Change d'onglet et resynchronise l'écran.
  ///
  /// L'écran ne bouge pas tout seul quand un joueur répond pendant qu'on
  /// prépare le match : sans ce rechargement, « en direct » voudrait dire « au
  /// prochain rafraîchissement manuel ». Une composition en cours d'édition
  /// n'est jamais écrasée : on la laisse telle quelle.
  void _selectStep(_AdminStep next) {
    setState(() => _step = next);
    if (next != _AdminStep.effectif && next != _AdminStep.composition) return;
    final matchId = _selectedMatchId;
    if (matchId == null || _loading || _busy || _compositionDirty) return;
    unawaited(_loadWorkspace(matchId));
  }

  /// Décisions d'effectif telles qu'elles doivent apparaître à l'écran.
  ///
  /// Avant le match, le serveur convoque déjà tout joueur disponible : on
  /// reprend sa décision telle quelle, et un disponible encore sans décision
  /// est présenté hors effectif tant que l'admin n'a pas tranché.
  Map<String, ConvocationStatus> _effectifStatusesFor({
    required MatchConvocations convocations,
    required bool postMatch,
    required Set<String> actualPresent,
  }) {
    return {
      for (final player in convocations.players)
        if (postMatch && actualPresent.contains(player.participantId))
          player.participantId: ConvocationStatus.convoked
        else if (postMatch && player.isAvailable && !player.isGuest)
          player.participantId: ConvocationStatus.notConvoked
        else if (!postMatch && player.isGuest)
          player.participantId: ConvocationStatus.convoked
        else if (!postMatch &&
            player.convocationStatus != ConvocationStatus.notApplicable)
          player.participantId: player.convocationStatus
        else if (!postMatch && player.isAvailable)
          player.participantId: ConvocationStatus.notConvoked,
    };
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
    final matchInfo = _selectedMatchId == null
        ? null
        : ref.watch(matchInfoProvider(_selectedMatchId!)).valueOrNull;
    final isInternal = matchInfo?.isInternal ?? false;
    final kickoffAt = matchInfo?.kickoffAt ?? _convocations?.kickoffAt;
    final tooFarAway = isMatchTooFarAway(kickoffAt);
    final liveTooEarly = isMatchLiveTooEarly(kickoffAt);
    final predictionClosed = isMatchPredictionClosed(kickoffAt);
    final step = tooFarAway
        ? _AdminStep.info
        : (_step == _AdminStep.live && liveTooEarly)
            ? _AdminStep.effectif
            : (_step == _AdminStep.prediction && predictionClosed)
                ? (!isInternal && !liveTooEarly
                    ? _AdminStep.live
                    : _AdminStep.effectif)
                : _step;

    return RefreshIndicator(
      onRefresh: _loadMatches,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.sectionGap,
          AppSpacing.screenGutter,
          40,
        ),
        children: [
          if (_selectedMatchId != null)
            UpcomingMatchFixtureHeader(matchId: _selectedMatchId!),
          SegmentedButton<_AdminStep>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: _AdminStep.info, label: Text('Info')),
              if (!tooFarAway)
                const ButtonSegment(
                  value: _AdminStep.effectif,
                  label: Text('Effectif'),
                ),
              if (!tooFarAway)
                const ButtonSegment(
                  value: _AdminStep.composition,
                  label: Text('Compo'),
                ),
              if (!isInternal && !tooFarAway && !liveTooEarly)
                const ButtonSegment(
                  value: _AdminStep.live,
                  label: Text('Live'),
                ),
              if (widget.showPredictionStep &&
                  !isInternal &&
                  !tooFarAway &&
                  !predictionClosed)
                const ButtonSegment(
                  value: _AdminStep.prediction,
                  label: Text('Prono'),
                ),
            ],
            selected: {step},
            onSelectionChanged:
                _busy ? null : (value) => _selectStep(value.first),
          ),
          if (_busy) ...[
            const SizedBox(height: AppSpacing.contentGap),
            const GrintaLinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sectionGap),
            Text(_error!),
          ],
          const SizedBox(height: AppSpacing.sectionGap),
          if (step == _AdminStep.info && _selectedMatchId != null)
            MatchInfoTab(matchId: _selectedMatchId!)
          else if (step == _AdminStep.live && _selectedMatchId != null)
            MatchLiveTab(matchId: _selectedMatchId!)
          else if (step == _AdminStep.prediction && _selectedMatchId != null)
            InlineMatchPredictionCard(matchId: _selectedMatchId!)
          else if (step == _AdminStep.composition &&
              isInternal &&
              _selectedMatchId != null)
            InternalTeamCompositionView(
              matchId: _selectedMatchId!,
              editable: !_locked,
            )
          else if (_convocations != null && _composition != null)
            step == _AdminStep.effectif
                ? _buildEffectif()
                : _buildComposition(),
        ],
      ),
    );
  }
}
