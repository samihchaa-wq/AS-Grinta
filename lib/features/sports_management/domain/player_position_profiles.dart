// GÉNÉRÉ — ne pas modifier à la main sans le vouloir.
// Produit par `python3 tool/derive_position_profiles.py <archive.html>`
// Source : 62c629f9-ASGrintaarchives20132026.html
//
// Postes de référence des joueurs, dérivés des compositions réellement
// alignées par le club. Chaque titularisation archivée est projetée sur le
// poste le plus proche de la feuille de match, puis les saisons sont
// pondérées par récence (demi-vie 2 saisons, référence 2025-2026).
//
// C'est le socle des postes, pas leur état final : l'application y ajoute
// les compositions réellement alignées depuis, avec le poids de leur
// saison. Aucune saisie manuelle de poste nulle part.

library;

/// Saison de référence de la pondération.
///
/// Les poids de ce fichier y sont ancrés : l'historique lu en base est
/// pondéré avec la même formule et le même ancrage, pour que les deux
/// sources s'additionnent sans se déformer.
const int kPositionProfilesReferenceSeason = 2025;

/// Nombre de saisons au bout duquel une titularisation ne pèse plus que
/// la moitié.
const double kPositionProfilesHalfLifeSeasons = 2.0;

/// Dernière composition couverte par l'archive.
///
/// Tout ce qui précède cette date est déjà compté ici : reprendre ces
/// matchs depuis la base les compterait deux fois.
final DateTime kPositionProfilesCoverageEnd = DateTime.utc(2026, 5, 21);

/// Un poste occupé par un joueur, et le poids de ses passages à ce poste.
class PlayerPositionSample {
  const PlayerPositionSample(this.slotLabel, this.weight);

  /// Étiquette du poste, telle que `matchSheetSlots` la nomme.
  final String slotLabel;

  /// Somme pondérée de ses titularisations à ce poste. La valeur est
  /// absolue, pas un pourcentage : c'est ce qui permet d'y ajouter les
  /// matchs joués depuis.
  final double weight;
}

/// Postes de référence d'un joueur, du plus fréquent au moins fréquent.
class PlayerPositionProfile {
  const PlayerPositionProfile({
    required this.displayName,
    required this.appearances,
    required this.samples,
    required this.totalWeight,
  });

  /// Nom du joueur dans l'archive du club, à titre indicatif. Vide pour
  /// un joueur connu uniquement par les matchs joués dans l'app.
  final String displayName;

  /// Nombre de titularisations relevées, toutes saisons confondues.
  final int appearances;

  /// Postes occupés, triés par poids décroissant. Jamais vide.
  final List<PlayerPositionSample> samples;

  /// Somme des poids de toutes ses titularisations, y compris les
  /// postes trop rares pour figurer dans [samples]. C'est le
  /// dénominateur des parts : sans lui, tronquer la queue de
  /// distribution gonflerait artificiellement le poste principal.
  final double totalWeight;

  /// Part du temps de jeu passée à un poste, entre 0 et 1.
  double shareOf(String slotLabel) {
    if (totalWeight <= 0) return 0;
    for (final sample in samples) {
      if (sample.slotLabel == slotLabel) {
        return sample.weight / totalWeight;
      }
    }
    return 0;
  }

  /// Le poste où le joueur a le plus joué.
  String get mainSlotLabel => samples.first.slotLabel;

  /// Son second poste, s'il en a réellement un.
  String? get secondarySlotLabel =>
      samples.length > 1 ? samples[1].slotLabel : null;

  /// Vrai quand aucun poste ne domine : le joueur est un couteau
  /// suisse, que la simulation place en ajustement plutôt que sur
  /// un poste de référence qui n'en est pas un.
  bool get isVersatile => shareOf(mainSlotLabel) < 0.3;
}

/// Profils indexés par identité canonique (`players.id`).
///
/// L'identité canonique traverse les saisons et les changements de nom,
/// contrairement à `season_players.id` ou au nom affiché.
const Map<String, PlayerPositionProfile> kPlayerPositionProfiles =
    <String, PlayerPositionProfile>{
  // Aki Salabee — MOD 25%, DCG 16%, MDC 14%, MOG 14%, DCD 10%, DG 10%
  '6aa3588d-4131-444e-802c-5a0913244831': PlayerPositionProfile(
    displayName: 'Aki Salabee',
    appearances: 20,
    totalWeight: 16.7782,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('MOD', 4.1213),
      PlayerPositionSample('DCG', 2.7071),
      PlayerPositionSample('MDC', 2.4142),
      PlayerPositionSample('MOG', 2.4142),
      PlayerPositionSample('DCD', 1.7071),
      PlayerPositionSample('DG', 1.7071),
    ],
  ),
  // Alban Ricard — MOD 44%, MOG 22%, AD 17%, AG 6%, BUD 6%, MOC 6%
  'a595c2c2-be69-430c-8dd5-6bbaa2dd7a65': PlayerPositionProfile(
    displayName: 'Alban Ricard',
    appearances: 18,
    totalWeight: 18.0000,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('MOD', 8.0000),
      PlayerPositionSample('MOG', 4.0000),
      PlayerPositionSample('AD', 3.0000),
      PlayerPositionSample('AG', 1.0000),
      PlayerPositionSample('BUD', 1.0000),
      PlayerPositionSample('MOC', 1.0000),
    ],
  ),
  // Allan Bamokena — AD 94%, AG 6%
  '9af382c3-7df3-4109-8c07-601754f19f89': PlayerPositionProfile(
    displayName: 'Allan Bamokena',
    appearances: 18,
    totalWeight: 18.0000,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('AD', 17.0000),
      PlayerPositionSample('AG', 1.0000),
    ],
  ),
  // Alyoun Cherfi — DG 84%, DCG 7%, DD 5%, GB 5%
  '2c40dbe5-a804-4b9f-9256-432ab85ce495': PlayerPositionProfile(
    displayName: 'Alyoun Cherfi',
    appearances: 37,
    totalWeight: 30.5563,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('DG', 25.7279),
      PlayerPositionSample('DCG', 2.0000),
      PlayerPositionSample('DD', 1.4142),
      PlayerPositionSample('GB', 1.4142),
    ],
  ),
  // Amine Salhi — DG 43%, DD 32%, AG 19%, AD 6%
  '76090b90-b1e6-46e0-90ba-4e91445b7fbd': PlayerPositionProfile(
    displayName: 'Amine Salhi',
    appearances: 16,
    totalWeight: 15.7071,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('DG', 6.7071),
      PlayerPositionSample('DD', 5.0000),
      PlayerPositionSample('AG', 3.0000),
      PlayerPositionSample('AD', 1.0000),
    ],
  ),
  // Anis Messaoudi — DG 33%, AD 22%, AG 11%, DD 11%, MOD 11%, MOG 11%
  '298bb51f-7e2f-4479-8fb9-254ceaf47ed8': PlayerPositionProfile(
    displayName: 'Anis Messaoudi',
    appearances: 9,
    totalWeight: 9.0000,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('DG', 3.0000),
      PlayerPositionSample('AD', 2.0000),
      PlayerPositionSample('AG', 1.0000),
      PlayerPositionSample('DD', 1.0000),
      PlayerPositionSample('MOD', 1.0000),
      PlayerPositionSample('MOG', 1.0000),
    ],
  ),
  // Anthony Massip — MCD 55%, DCG 45%
  '2e059d08-d036-4ca3-9b38-f144418e1eb8': PlayerPositionProfile(
    displayName: 'Anthony Massip',
    appearances: 4,
    totalWeight: 0.3902,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('MCD', 0.2134),
      PlayerPositionSample('DCG', 0.1768),
    ],
  ),
  // Arnold Hajdini — MD 23%, MG 19%, AD 12%, AG 9%, BUG 9%, BU 8%
  'b981ee78-b071-4d9d-a16a-6198aa177491': PlayerPositionProfile(
    displayName: 'Arnold Hajdini',
    appearances: 43,
    totalWeight: 15.9069,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('MD', 3.6642),
      PlayerPositionSample('MG', 3.0178),
      PlayerPositionSample('AD', 1.9571),
      PlayerPositionSample('AG', 1.3536),
      PlayerPositionSample('BUG', 1.3536),
      PlayerPositionSample('BU', 1.2071),
    ],
  ),
  // Clément Gaudefroy — BU 33%, BUD 33%, GB 33%
  '46ba5817-0a5b-4373-b144-a3708ffbf190': PlayerPositionProfile(
    displayName: 'Clément Gaudefroy',
    appearances: 3,
    totalWeight: 0.2652,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('BU', 0.0884),
      PlayerPositionSample('BUD', 0.0884),
      PlayerPositionSample('GB', 0.0884),
    ],
  ),
  // Dorian Larrieu — DD 61%, DCD 23%, DCG 13%
  '16aa496f-798f-4d39-b5db-361fb3288022': PlayerPositionProfile(
    displayName: 'Dorian Larrieu',
    appearances: 40,
    totalWeight: 11.7301,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('DD', 7.1391),
      PlayerPositionSample('DCD', 2.6705),
      PlayerPositionSample('DCG', 1.4786),
    ],
  ),
  // Elvis Alves — MOC 50%, AD 25%, AG 25%
  '114677c4-abaf-4ab8-8909-7f8077885723': PlayerPositionProfile(
    displayName: 'Elvis Alves',
    appearances: 4,
    totalWeight: 1.0000,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('MOC', 0.5000),
      PlayerPositionSample('AD', 0.2500),
      PlayerPositionSample('AG', 0.2500),
    ],
  ),
  // Emeric Chincholle — MD 50%, MG 50%
  'e29ddb1f-2b1c-42da-9cf8-15cb93628b08': PlayerPositionProfile(
    displayName: 'Emeric Chincholle',
    appearances: 4,
    totalWeight: 0.5000,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('MD', 0.2500),
      PlayerPositionSample('MG', 0.2500),
    ],
  ),
  // Flo Arnauduc — MOG 38%, MDC 18%, MDG 12%, MOC 11%, MCG 10%, AG 4%
  '1343e65c-63fa-4f8f-af56-56d3136962b5': PlayerPositionProfile(
    displayName: 'Flo Arnauduc',
    appearances: 132,
    totalWeight: 60.8582,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('MOG', 22.8995),
      PlayerPositionSample('MDC', 10.8284),
      PlayerPositionSample('MDG', 7.3070),
      PlayerPositionSample('MOC', 6.4660),
      PlayerPositionSample('MCG', 5.7878),
      PlayerPositionSample('AG', 2.5000),
    ],
  ),
  // Florian Poulichet — BUD 34%, BUG 27%, AG 14%, GB 10%, BU 7%, MG 7%
  '5f09a6cc-b306-427e-b5c2-37551e058245': PlayerPositionProfile(
    displayName: 'Florian Poulichet',
    appearances: 11,
    totalWeight: 1.2437,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('BUD', 0.4268),
      PlayerPositionSample('BUG', 0.3384),
      PlayerPositionSample('AG', 0.1768),
      PlayerPositionSample('GB', 0.1250),
      PlayerPositionSample('BU', 0.0884),
      PlayerPositionSample('MG', 0.0884),
    ],
  ),
  // François De La Bourdonnaye — AG 56%, MG 23%, BU 7%, DG 7%, BUG 5%
  '8998ddff-122c-414b-899d-757c1c4f170a': PlayerPositionProfile(
    displayName: 'François De La Bourdonnaye',
    appearances: 58,
    totalWeight: 26.7029,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('AG', 14.9121),
      PlayerPositionSample('MG', 6.0440),
      PlayerPositionSample('BU', 1.9571),
      PlayerPositionSample('DG', 1.7955),
      PlayerPositionSample('BUG', 1.3692),
    ],
  ),
  // Frédéric Hermet — MCG 40%, MCD 20%, MDG 13%, BUD 7%, DCG 7%, GB 7%
  'a26bcec5-af3f-42ee-8a66-1b954bc8f8f6': PlayerPositionProfile(
    displayName: 'Frédéric Hermet',
    appearances: 14,
    totalWeight: 1.8750,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('MCG', 0.7500),
      PlayerPositionSample('MCD', 0.3750),
      PlayerPositionSample('MDG', 0.2500),
      PlayerPositionSample('BUD', 0.1250),
      PlayerPositionSample('DCG', 0.1250),
      PlayerPositionSample('GB', 0.1250),
    ],
  ),
  // Guillaume Andret — GB 92%, BUD 8%
  '3145408a-d9cb-4a41-907e-fb054cc2a1b5': PlayerPositionProfile(
    displayName: 'Guillaume Andret',
    appearances: 9,
    totalWeight: 0.9808,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('GB', 0.9053),
      PlayerPositionSample('BUD', 0.0754),
    ],
  ),
  // Hakim Cherfi — DCD 17%, AG 16%, AD 15%, DD 13%, MD 12%, DCG 9%
  'aaa132f5-1fca-47dc-a875-5c2aaa4a9ae9': PlayerPositionProfile(
    displayName: 'Hakim Cherfi',
    appearances: 38,
    totalWeight: 24.7886,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('DCD', 4.2071),
      PlayerPositionSample('AG', 3.9749),
      PlayerPositionSample('AD', 3.8284),
      PlayerPositionSample('DD', 3.1213),
      PlayerPositionSample('MD', 2.9749),
      PlayerPositionSample('DCG', 2.2071),
    ],
  ),
  // Julien Cesar — DCG 81%, DCD 8%, DG 4%
  'a1cac6b7-ef09-493f-9d3e-7078fcaa3d97': PlayerPositionProfile(
    displayName: 'Julien Cesar',
    appearances: 72,
    totalWeight: 33.7520,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('DCG', 27.3200),
      PlayerPositionSample('DCD', 2.6124),
      PlayerPositionSample('DG', 1.3839),
    ],
  ),
  // Julio Vignard — DD 55%, DG 10%, MDG 5%
  '2e161341-e2b5-48d2-b852-717be71024aa': PlayerPositionProfile(
    displayName: 'Julio Vignard',
    appearances: 75,
    totalWeight: 37.6003,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('DD', 20.8640),
      PlayerPositionSample('DG', 3.7071),
      PlayerPositionSample('MDG', 2.0152),
    ],
  ),
  // Kevin Jagot — AD 42%, MD 25%, AG 10%, BU 4%, MOC 4%
  '36d6011f-b24f-4264-b43a-ea5f93147c93': PlayerPositionProfile(
    displayName: 'Kevin Jagot',
    appearances: 88,
    totalWeight: 29.1662,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('AD', 12.2845),
      PlayerPositionSample('MD', 7.3436),
      PlayerPositionSample('AG', 2.8562),
      PlayerPositionSample('BU', 1.2071),
      PlayerPositionSample('MOC', 1.2071),
    ],
  ),
  // Luka Brunel — MOD 45%, MOG 16%, MDD 13%, MDG 7%, MCD 6%, MOC 5%
  'b9f696f7-297d-4891-96f1-34a974c0f7a1': PlayerPositionProfile(
    displayName: 'Luka Brunel',
    appearances: 93,
    totalWeight: 53.5490,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('MOD', 23.8388),
      PlayerPositionSample('MOG', 8.7678),
      PlayerPositionSample('MDD', 6.8284),
      PlayerPositionSample('MDG', 3.5178),
      PlayerPositionSample('MCD', 3.4749),
      PlayerPositionSample('MOC', 2.5607),
    ],
  ),
  // Mathieu Barthe — BUG 35%, MOC 23%, BU 19%, BUD 12%, DCG 5%
  '226b8676-de68-4486-b5f6-dda7526018be': PlayerPositionProfile(
    displayName: 'Mathieu Barthe',
    appearances: 32,
    totalWeight: 4.2696,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('BUG', 1.4737),
      PlayerPositionSample('MOC', 1.0000),
      PlayerPositionSample('BU', 0.8018),
      PlayerPositionSample('BUD', 0.5000),
      PlayerPositionSample('DCG', 0.2134),
    ],
  ),
  // Mathieu Bergon — BUD 30%, MCD 30%, BUG 16%, MOC 12%, AD 6%, AG 6%
  'cb653166-360c-4545-b63c-42c240a84007': PlayerPositionProfile(
    displayName: 'Mathieu Bergon',
    appearances: 13,
    totalWeight: 1.5303,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('BUD', 0.4634),
      PlayerPositionSample('MCD', 0.4634),
      PlayerPositionSample('BUG', 0.2500),
      PlayerPositionSample('MOC', 0.1768),
      PlayerPositionSample('AD', 0.0884),
      PlayerPositionSample('AG', 0.0884),
    ],
  ),
  // Mehdi Liauzun — MOD 33%, MOG 33%, AD 27%, AG 7%
  'cfcdf327-0654-43bf-a729-3186ad39045d': PlayerPositionProfile(
    displayName: 'Mehdi Liauzun',
    appearances: 15,
    totalWeight: 10.6066,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('MOD', 3.5355),
      PlayerPositionSample('MOG', 3.5355),
      PlayerPositionSample('AD', 2.8284),
      PlayerPositionSample('AG', 0.7071),
    ],
  ),
  // Milan Couzin — BU 81%, BUD 7%, BUG 7%, MOC 4%
  '5c681291-ec75-47ed-8bee-1b538b69cefe': PlayerPositionProfile(
    displayName: 'Milan Couzin',
    appearances: 123,
    totalWeight: 68.3272,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('BU', 55.3774),
      PlayerPositionSample('BUD', 5.0178),
      PlayerPositionSample('BUG', 5.0178),
      PlayerPositionSample('MOC', 2.9142),
    ],
  ),
  // Nico Galvan — BUD 67%, AG 17%, DD 17%
  'f1fb2521-e9a9-43e3-b7f2-0359808890d0': PlayerPositionProfile(
    displayName: 'Nico Galvan',
    appearances: 6,
    totalWeight: 0.7500,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('BUD', 0.5000),
      PlayerPositionSample('AG', 0.1250),
      PlayerPositionSample('DD', 0.1250),
    ],
  ),
  // Nicolas Belmonte — AG 79%, BU 14%, MOG 7%
  '4bbdab69-6f29-430d-8c05-eb8bc4b1e547': PlayerPositionProfile(
    displayName: 'Nicolas Belmonte',
    appearances: 14,
    totalWeight: 14.0000,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('AG', 11.0000),
      PlayerPositionSample('BU', 2.0000),
      PlayerPositionSample('MOG', 1.0000),
    ],
  ),
  // Olivier Millet — DCD 50%, DCG 23%, DD 18%, DG 4%
  'b26acaab-3d33-4371-a80f-5692ffb6d026': PlayerPositionProfile(
    displayName: 'Olivier Millet',
    appearances: 109,
    totalWeight: 46.7369,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('DCD', 23.4173),
      PlayerPositionSample('DCG', 10.5784),
      PlayerPositionSample('DD', 8.3310),
      PlayerPositionSample('DG', 2.0695),
    ],
  ),
  // Quentin Derbois — BUD 37%, BUG 34%, MOC 18%, GB 11%
  '257e639d-0621-4015-acef-d69e74e45bb2': PlayerPositionProfile(
    displayName: 'Quentin Derbois',
    appearances: 11,
    totalWeight: 1.1553,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('BUD', 0.4268),
      PlayerPositionSample('BUG', 0.3902),
      PlayerPositionSample('MOC', 0.2134),
      PlayerPositionSample('GB', 0.1250),
    ],
  ),
  // Romain Spigolon — MDC 55%, MC 11%, MDD 10%, MDG 8%, MCD 4%
  'aba6998e-e020-4e62-9b35-4a9583ca5ad9': PlayerPositionProfile(
    displayName: 'Romain Spigolon',
    appearances: 110,
    totalWeight: 49.4271,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('MDC', 27.0459),
      PlayerPositionSample('MC', 5.2860),
      PlayerPositionSample('MDD', 4.9017),
      PlayerPositionSample('MDG', 3.8410),
      PlayerPositionSample('MCD', 2.1209),
    ],
  ),
  // Roman Yassinski — MDD 23%, AD 14%, MD 13%, MOD 11%, MDG 8%, MC 8%
  '44626628-08b5-4b91-b021-f15372b71538': PlayerPositionProfile(
    displayName: 'Roman Yassinski',
    appearances: 50,
    totalWeight: 20.1495,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('MDD', 4.7071),
      PlayerPositionSample('AD', 2.8284),
      PlayerPositionSample('MD', 2.6642),
      PlayerPositionSample('MOD', 2.2678),
      PlayerPositionSample('MDG', 1.7071),
      PlayerPositionSample('MC', 1.5607),
    ],
  ),
  // Samih Châa — GB 100%
  '89f24276-dac0-4046-87a3-6c28e48fef3a': PlayerPositionProfile(
    displayName: 'Samih Châa',
    appearances: 117,
    totalWeight: 60.9381,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('GB', 60.9381),
    ],
  ),
  // Samih Châa — GB 100%
  'f971cfdd-a07a-430f-93b4-d5373600a180': PlayerPositionProfile(
    displayName: 'Samih Châa',
    appearances: 117,
    totalWeight: 60.9381,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('GB', 60.9381),
    ],
  ),
  // Samuel Granier — DD 53%, GB 21%, AD 9%, AG 6%, DG 5%
  'c5ba5eda-9cb3-4ec5-aa68-eef33b84a3ad': PlayerPositionProfile(
    displayName: 'Samuel Granier',
    appearances: 98,
    totalWeight: 47.3387,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('DD', 25.0722),
      PlayerPositionSample('GB', 9.8070),
      PlayerPositionSample('AD', 4.3284),
      PlayerPositionSample('AG', 2.7071),
      PlayerPositionSample('DG', 2.2589),
    ],
  ),
  // Sebastien Seillier — DCG 47%, DCD 45%, MDG 4%
  'efeecb6e-53b1-4f9d-b0b4-44a1013571a2': PlayerPositionProfile(
    displayName: 'Sebastien Seillier',
    appearances: 35,
    totalWeight: 5.7254,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('DCG', 2.6946),
      PlayerPositionSample('DCD', 2.5518),
      PlayerPositionSample('MDG', 0.2500),
    ],
  ),
  // Simon Reis — DCD 24%, DCG 17%, AG 10%, DG 9%, MOC 8%, MDC 7%
  'af7dfe56-0be5-4d5c-8dda-140a99df7dbf': PlayerPositionProfile(
    displayName: 'Simon Reis',
    appearances: 41,
    totalWeight: 20.7708,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('DCD', 4.9749),
      PlayerPositionSample('DCG', 3.6213),
      PlayerPositionSample('AG', 2.0000),
      PlayerPositionSample('DG', 1.9142),
      PlayerPositionSample('MOC', 1.7071),
      PlayerPositionSample('MDC', 1.4142),
    ],
  ),
  // Stéphane Fernandez — DCD 55%, DCG 38%, DC 7%
  '7fe67f9b-75c0-4606-8030-021b00900cc1': PlayerPositionProfile(
    displayName: 'Stéphane Fernandez',
    appearances: 119,
    totalWeight: 59.2179,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('DCD', 32.5025),
      PlayerPositionSample('DCG', 22.3440),
      PlayerPositionSample('DC', 4.2463),
    ],
  ),
  // Stéphane Manenti — DG 93%, AG 4%
  '665fcf3b-eace-4ae0-97a8-498f9bf918f5': PlayerPositionProfile(
    displayName: 'Stéphane Manenti',
    appearances: 71,
    totalWeight: 17.2157,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('DG', 16.0300),
      PlayerPositionSample('AG', 0.7071),
    ],
  ),
  // Thomas Blanchard — DG 52%, MG 16%, DD 16%, AG 14%
  'c0db4bc0-7725-4721-834b-0850e3c1e2a3': PlayerPositionProfile(
    displayName: 'Thomas Blanchard',
    appearances: 63,
    totalWeight: 23.2959,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('DG', 12.0962),
      PlayerPositionSample('MG', 3.7678),
      PlayerPositionSample('DD', 3.6213),
      PlayerPositionSample('AG', 3.3107),
    ],
  ),
  // Vincent Rouch — DD 71%, GB 29%
  '51a58cdb-30fa-4dce-8c30-c4957a7f8776': PlayerPositionProfile(
    displayName: 'Vincent Rouch',
    appearances: 4,
    totalWeight: 0.3094,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('DD', 0.2210),
      PlayerPositionSample('GB', 0.0884),
    ],
  ),
  // Xavier Grossin — GB 100%
  '35ad373d-fb20-482d-85e7-f7e7eaf93404': PlayerPositionProfile(
    displayName: 'Xavier Grossin',
    appearances: 3,
    totalWeight: 1.9142,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('GB', 1.9142),
    ],
  ),
  // Yoann Canal — AG 23%, BU 17%, AD 17%, BUD 17%, BUG 11%, MOC 10%
  'db3112de-05f3-43c9-aa0c-46a87a07d409': PlayerPositionProfile(
    displayName: 'Yoann Canal',
    appearances: 36,
    totalWeight: 18.2279,
    samples: <PlayerPositionSample>[
      PlayerPositionSample('AG', 4.2426),
      PlayerPositionSample('BU', 3.1213),
      PlayerPositionSample('AD', 3.1213),
      PlayerPositionSample('BUD', 3.0607),
      PlayerPositionSample('BUG', 2.0607),
      PlayerPositionSample('MOC', 1.7678),
    ],
  ),
};
