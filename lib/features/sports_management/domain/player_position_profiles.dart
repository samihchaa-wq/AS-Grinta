// GÉNÉRÉ — ne pas modifier à la main sans le vouloir.
// Produit par `python3 tool/derive_position_profiles.py <archive.html>`
// Source : 62c629f9-ASGrintaarchives20132026.html
//
// Postes de référence des joueurs, dérivés des compositions réellement
// alignées par le club. Chaque titularisation archivée est projetée sur le
// poste le plus proche de la feuille de match, puis les saisons sont
// pondérées par récence (demi-vie 2 saisons, référence 2025-2026).
//
// C'est la source permanente des postes : ni la base ni l'application ne
// permettent de les saisir.

library;

/// Part du temps de jeu passée par un joueur à un poste donné.
class PlayerPositionShare {
  const PlayerPositionShare(this.slotLabel, this.share);

  /// Étiquette du poste, telle que `matchSheetSlots` la nomme.
  final String slotLabel;

  /// Part pondérée de ses titularisations à ce poste, entre 0 et 1.
  final double share;
}

/// Postes de référence d'un joueur, du plus fréquent au moins fréquent.
class PlayerPositionProfile {
  const PlayerPositionProfile({
    required this.displayName,
    required this.appearances,
    required this.shares,
  });

  /// Nom du joueur dans l'archive du club, à titre indicatif.
  final String displayName;

  /// Nombre de titularisations relevées, toutes saisons confondues.
  final int appearances;

  /// Postes occupés, triés par part décroissante. Jamais vide.
  final List<PlayerPositionShare> shares;

  /// Le poste où le joueur a le plus joué.
  String get mainSlotLabel => shares.first.slotLabel;

  /// Son second poste, s'il en a réellement un.
  String? get secondarySlotLabel =>
      shares.length > 1 ? shares[1].slotLabel : null;

  /// Vrai quand aucun poste ne domine : le joueur est un couteau
  /// suisse, que la simulation place en ajustement plutôt que sur
  /// un poste de référence qui n'en est pas un.
  bool get isVersatile => shares.first.share < 0.3;
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
    shares: <PlayerPositionShare>[
      PlayerPositionShare('MOD', 0.2456),
      PlayerPositionShare('DCG', 0.1613),
      PlayerPositionShare('MDC', 0.1439),
      PlayerPositionShare('MOG', 0.1439),
      PlayerPositionShare('DCD', 0.1017),
      PlayerPositionShare('DG', 0.1017),
    ],
  ),
  // Alban Ricard — MOD 44%, MOG 22%, AD 17%, AG 6%, BUD 6%, MOC 6%
  'a595c2c2-be69-430c-8dd5-6bbaa2dd7a65': PlayerPositionProfile(
    displayName: 'Alban Ricard',
    appearances: 18,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('MOD', 0.4444),
      PlayerPositionShare('MOG', 0.2222),
      PlayerPositionShare('AD', 0.1667),
      PlayerPositionShare('AG', 0.0556),
      PlayerPositionShare('BUD', 0.0556),
      PlayerPositionShare('MOC', 0.0556),
    ],
  ),
  // Allan Bamokena — AD 94%, AG 6%
  '9af382c3-7df3-4109-8c07-601754f19f89': PlayerPositionProfile(
    displayName: 'Allan Bamokena',
    appearances: 18,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('AD', 0.9444),
      PlayerPositionShare('AG', 0.0556),
    ],
  ),
  // Alyoun Cherfi — DG 84%, DCG 7%, DD 5%, GB 5%
  '2c40dbe5-a804-4b9f-9256-432ab85ce495': PlayerPositionProfile(
    displayName: 'Alyoun Cherfi',
    appearances: 37,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('DG', 0.8420),
      PlayerPositionShare('DCG', 0.0655),
      PlayerPositionShare('DD', 0.0463),
      PlayerPositionShare('GB', 0.0463),
    ],
  ),
  // Amine Salhi — DG 43%, DD 32%, AG 19%, AD 6%
  '76090b90-b1e6-46e0-90ba-4e91445b7fbd': PlayerPositionProfile(
    displayName: 'Amine Salhi',
    appearances: 16,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('DG', 0.4270),
      PlayerPositionShare('DD', 0.3183),
      PlayerPositionShare('AG', 0.1910),
      PlayerPositionShare('AD', 0.0637),
    ],
  ),
  // Anis Messaoudi — DG 33%, AD 22%, AG 11%, DD 11%, MOD 11%, MOG 11%
  '298bb51f-7e2f-4479-8fb9-254ceaf47ed8': PlayerPositionProfile(
    displayName: 'Anis Messaoudi',
    appearances: 9,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('DG', 0.3333),
      PlayerPositionShare('AD', 0.2222),
      PlayerPositionShare('AG', 0.1111),
      PlayerPositionShare('DD', 0.1111),
      PlayerPositionShare('MOD', 0.1111),
      PlayerPositionShare('MOG', 0.1111),
    ],
  ),
  // Anthony Massip — MCD 55%, DCG 45%
  '2e059d08-d036-4ca3-9b38-f144418e1eb8': PlayerPositionProfile(
    displayName: 'Anthony Massip',
    appearances: 4,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('MCD', 0.5469),
      PlayerPositionShare('DCG', 0.4531),
    ],
  ),
  // Arnold Hajdini — MD 23%, MG 19%, AD 12%, AG 9%, BUG 9%, BU 8%
  'b981ee78-b071-4d9d-a16a-6198aa177491': PlayerPositionProfile(
    displayName: 'Arnold Hajdini',
    appearances: 43,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('MD', 0.2304),
      PlayerPositionShare('MG', 0.1897),
      PlayerPositionShare('AD', 0.1230),
      PlayerPositionShare('AG', 0.0851),
      PlayerPositionShare('BUG', 0.0851),
      PlayerPositionShare('BU', 0.0759),
    ],
  ),
  // Clément Gaudefroy — BU 33%, BUD 33%, GB 33%
  '46ba5817-0a5b-4373-b144-a3708ffbf190': PlayerPositionProfile(
    displayName: 'Clément Gaudefroy',
    appearances: 3,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('BU', 0.3333),
      PlayerPositionShare('BUD', 0.3333),
      PlayerPositionShare('GB', 0.3333),
    ],
  ),
  // Dorian Larrieu — DD 61%, DCD 23%, DCG 13%
  '16aa496f-798f-4d39-b5db-361fb3288022': PlayerPositionProfile(
    displayName: 'Dorian Larrieu',
    appearances: 40,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('DD', 0.6086),
      PlayerPositionShare('DCD', 0.2277),
      PlayerPositionShare('DCG', 0.1260),
    ],
  ),
  // Elvis Alves — MOC 50%, AD 25%, AG 25%
  '114677c4-abaf-4ab8-8909-7f8077885723': PlayerPositionProfile(
    displayName: 'Elvis Alves',
    appearances: 4,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('MOC', 0.5000),
      PlayerPositionShare('AD', 0.2500),
      PlayerPositionShare('AG', 0.2500),
    ],
  ),
  // Emeric Chincholle — MD 50%, MG 50%
  'e29ddb1f-2b1c-42da-9cf8-15cb93628b08': PlayerPositionProfile(
    displayName: 'Emeric Chincholle',
    appearances: 4,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('MD', 0.5000),
      PlayerPositionShare('MG', 0.5000),
    ],
  ),
  // Flo Arnauduc — MOG 38%, MDC 18%, MDG 12%, MOC 11%, MCG 10%, AG 4%
  '1343e65c-63fa-4f8f-af56-56d3136962b5': PlayerPositionProfile(
    displayName: 'Flo Arnauduc',
    appearances: 132,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('MOG', 0.3763),
      PlayerPositionShare('MDC', 0.1779),
      PlayerPositionShare('MDG', 0.1201),
      PlayerPositionShare('MOC', 0.1062),
      PlayerPositionShare('MCG', 0.0951),
      PlayerPositionShare('AG', 0.0411),
    ],
  ),
  // Florian Poulichet — BUD 34%, BUG 27%, AG 14%, GB 10%, BU 7%, MG 7%
  '5f09a6cc-b306-427e-b5c2-37551e058245': PlayerPositionProfile(
    displayName: 'Florian Poulichet',
    appearances: 11,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('BUD', 0.3431),
      PlayerPositionShare('BUG', 0.2721),
      PlayerPositionShare('AG', 0.1421),
      PlayerPositionShare('GB', 0.1005),
      PlayerPositionShare('BU', 0.0711),
      PlayerPositionShare('MG', 0.0711),
    ],
  ),
  // François De La Bourdonnaye — AG 56%, MG 23%, BU 7%, DG 7%, BUG 5%
  '8998ddff-122c-414b-899d-757c1c4f170a': PlayerPositionProfile(
    displayName: 'François De La Bourdonnaye',
    appearances: 58,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('AG', 0.5584),
      PlayerPositionShare('MG', 0.2263),
      PlayerPositionShare('BU', 0.0733),
      PlayerPositionShare('DG', 0.0672),
      PlayerPositionShare('BUG', 0.0513),
    ],
  ),
  // Frédéric Hermet — MCG 40%, MCD 20%, MDG 13%, BUD 7%, DCG 7%, GB 7%
  'a26bcec5-af3f-42ee-8a66-1b954bc8f8f6': PlayerPositionProfile(
    displayName: 'Frédéric Hermet',
    appearances: 14,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('MCG', 0.4000),
      PlayerPositionShare('MCD', 0.2000),
      PlayerPositionShare('MDG', 0.1333),
      PlayerPositionShare('BUD', 0.0667),
      PlayerPositionShare('DCG', 0.0667),
      PlayerPositionShare('GB', 0.0667),
    ],
  ),
  // Guillaume Andret — GB 92%, BUD 8%
  '3145408a-d9cb-4a41-907e-fb054cc2a1b5': PlayerPositionProfile(
    displayName: 'Guillaume Andret',
    appearances: 9,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('GB', 0.9231),
      PlayerPositionShare('BUD', 0.0769),
    ],
  ),
  // Hakim Cherfi — DCD 17%, AG 16%, AD 15%, DD 13%, MD 12%, DCG 9%
  'aaa132f5-1fca-47dc-a875-5c2aaa4a9ae9': PlayerPositionProfile(
    displayName: 'Hakim Cherfi',
    appearances: 38,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('DCD', 0.1697),
      PlayerPositionShare('AG', 0.1604),
      PlayerPositionShare('AD', 0.1544),
      PlayerPositionShare('DD', 0.1259),
      PlayerPositionShare('MD', 0.1200),
      PlayerPositionShare('DCG', 0.0890),
    ],
  ),
  // Julien Cesar — DCG 81%, DCD 8%, DG 4%
  'a1cac6b7-ef09-493f-9d3e-7078fcaa3d97': PlayerPositionProfile(
    displayName: 'Julien Cesar',
    appearances: 72,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('DCG', 0.8094),
      PlayerPositionShare('DCD', 0.0774),
      PlayerPositionShare('DG', 0.0410),
    ],
  ),
  // Julio Vignard — DD 55%, DG 10%, MDG 5%
  '2e161341-e2b5-48d2-b852-717be71024aa': PlayerPositionProfile(
    displayName: 'Julio Vignard',
    appearances: 75,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('DD', 0.5549),
      PlayerPositionShare('DG', 0.0986),
      PlayerPositionShare('MDG', 0.0536),
    ],
  ),
  // Kevin Jagot — AD 42%, MD 25%, AG 10%, BU 4%, MOC 4%
  '36d6011f-b24f-4264-b43a-ea5f93147c93': PlayerPositionProfile(
    displayName: 'Kevin Jagot',
    appearances: 88,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('AD', 0.4212),
      PlayerPositionShare('MD', 0.2518),
      PlayerPositionShare('AG', 0.0979),
      PlayerPositionShare('BU', 0.0414),
      PlayerPositionShare('MOC', 0.0414),
    ],
  ),
  // Luka Brunel — MOD 45%, MOG 16%, MDD 13%, MDG 7%, MCD 6%, MOC 5%
  'b9f696f7-297d-4891-96f1-34a974c0f7a1': PlayerPositionProfile(
    displayName: 'Luka Brunel',
    appearances: 93,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('MOD', 0.4452),
      PlayerPositionShare('MOG', 0.1637),
      PlayerPositionShare('MDD', 0.1275),
      PlayerPositionShare('MDG', 0.0657),
      PlayerPositionShare('MCD', 0.0649),
      PlayerPositionShare('MOC', 0.0478),
    ],
  ),
  // Mathieu Barthe — BUG 35%, MOC 23%, BU 19%, BUD 12%, DCG 5%
  '226b8676-de68-4486-b5f6-dda7526018be': PlayerPositionProfile(
    displayName: 'Mathieu Barthe',
    appearances: 32,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('BUG', 0.3451),
      PlayerPositionShare('MOC', 0.2342),
      PlayerPositionShare('BU', 0.1878),
      PlayerPositionShare('BUD', 0.1171),
      PlayerPositionShare('DCG', 0.0500),
    ],
  ),
  // Mathieu Bergon — BUD 30%, MCD 30%, BUG 16%, MOC 12%, AD 6%, AG 6%
  'cb653166-360c-4545-b63c-42c240a84007': PlayerPositionProfile(
    displayName: 'Mathieu Bergon',
    appearances: 13,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('BUD', 0.3028),
      PlayerPositionShare('MCD', 0.3028),
      PlayerPositionShare('BUG', 0.1634),
      PlayerPositionShare('MOC', 0.1155),
      PlayerPositionShare('AD', 0.0578),
      PlayerPositionShare('AG', 0.0578),
    ],
  ),
  // Mehdi Liauzun — MOD 33%, MOG 33%, AD 27%, AG 7%
  'cfcdf327-0654-43bf-a729-3186ad39045d': PlayerPositionProfile(
    displayName: 'Mehdi Liauzun',
    appearances: 15,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('MOD', 0.3333),
      PlayerPositionShare('MOG', 0.3333),
      PlayerPositionShare('AD', 0.2667),
      PlayerPositionShare('AG', 0.0667),
    ],
  ),
  // Milan Couzin — BU 81%, BUD 7%, BUG 7%, MOC 4%
  '5c681291-ec75-47ed-8bee-1b538b69cefe': PlayerPositionProfile(
    displayName: 'Milan Couzin',
    appearances: 123,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('BU', 0.8105),
      PlayerPositionShare('BUD', 0.0734),
      PlayerPositionShare('BUG', 0.0734),
      PlayerPositionShare('MOC', 0.0427),
    ],
  ),
  // Nico Galvan — BUD 67%, AG 17%, DD 17%
  'f1fb2521-e9a9-43e3-b7f2-0359808890d0': PlayerPositionProfile(
    displayName: 'Nico Galvan',
    appearances: 6,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('BUD', 0.6667),
      PlayerPositionShare('AG', 0.1667),
      PlayerPositionShare('DD', 0.1667),
    ],
  ),
  // Nicolas Belmonte — AG 79%, BU 14%, MOG 7%
  '4bbdab69-6f29-430d-8c05-eb8bc4b1e547': PlayerPositionProfile(
    displayName: 'Nicolas Belmonte',
    appearances: 14,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('AG', 0.7857),
      PlayerPositionShare('BU', 0.1429),
      PlayerPositionShare('MOG', 0.0714),
    ],
  ),
  // Olivier Millet — DCD 50%, DCG 23%, DD 18%, DG 4%
  'b26acaab-3d33-4371-a80f-5692ffb6d026': PlayerPositionProfile(
    displayName: 'Olivier Millet',
    appearances: 109,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('DCD', 0.5010),
      PlayerPositionShare('DCG', 0.2263),
      PlayerPositionShare('DD', 0.1783),
      PlayerPositionShare('DG', 0.0443),
    ],
  ),
  // Quentin Derbois — BUD 37%, BUG 34%, MOC 18%, GB 11%
  '257e639d-0621-4015-acef-d69e74e45bb2': PlayerPositionProfile(
    displayName: 'Quentin Derbois',
    appearances: 11,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('BUD', 0.3694),
      PlayerPositionShare('BUG', 0.3377),
      PlayerPositionShare('MOC', 0.1847),
      PlayerPositionShare('GB', 0.1082),
    ],
  ),
  // Romain Spigolon — MDC 55%, MC 11%, MDD 10%, MDG 8%, MCD 4%
  'aba6998e-e020-4e62-9b35-4a9583ca5ad9': PlayerPositionProfile(
    displayName: 'Romain Spigolon',
    appearances: 110,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('MDC', 0.5472),
      PlayerPositionShare('MC', 0.1069),
      PlayerPositionShare('MDD', 0.0992),
      PlayerPositionShare('MDG', 0.0777),
      PlayerPositionShare('MCD', 0.0429),
    ],
  ),
  // Roman Yassinski — MDD 23%, AD 14%, MD 13%, MOD 11%, MDG 8%, MC 8%
  '44626628-08b5-4b91-b021-f15372b71538': PlayerPositionProfile(
    displayName: 'Roman Yassinski',
    appearances: 50,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('MDD', 0.2336),
      PlayerPositionShare('AD', 0.1404),
      PlayerPositionShare('MD', 0.1322),
      PlayerPositionShare('MOD', 0.1125),
      PlayerPositionShare('MDG', 0.0847),
      PlayerPositionShare('MC', 0.0775),
    ],
  ),
  // Samih Châa — GB 100%
  '89f24276-dac0-4046-87a3-6c28e48fef3a': PlayerPositionProfile(
    displayName: 'Samih Châa',
    appearances: 117,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('GB', 1.0000),
    ],
  ),
  // Samih Châa — GB 100%
  'f971cfdd-a07a-430f-93b4-d5373600a180': PlayerPositionProfile(
    displayName: 'Samih Châa',
    appearances: 117,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('GB', 1.0000),
    ],
  ),
  // Samuel Granier — DD 53%, GB 21%, AD 9%, AG 6%, DG 5%
  'c5ba5eda-9cb3-4ec5-aa68-eef33b84a3ad': PlayerPositionProfile(
    displayName: 'Samuel Granier',
    appearances: 98,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('DD', 0.5296),
      PlayerPositionShare('GB', 0.2072),
      PlayerPositionShare('AD', 0.0914),
      PlayerPositionShare('AG', 0.0572),
      PlayerPositionShare('DG', 0.0477),
    ],
  ),
  // Sebastien Seillier — DCG 47%, DCD 45%, MDG 4%
  'efeecb6e-53b1-4f9d-b0b4-44a1013571a2': PlayerPositionProfile(
    displayName: 'Sebastien Seillier',
    appearances: 35,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('DCG', 0.4706),
      PlayerPositionShare('DCD', 0.4457),
      PlayerPositionShare('MDG', 0.0437),
    ],
  ),
  // Simon Reis — DCD 24%, DCG 17%, AG 10%, DG 9%, MOC 8%, MDC 7%
  'af7dfe56-0be5-4d5c-8dda-140a99df7dbf': PlayerPositionProfile(
    displayName: 'Simon Reis',
    appearances: 41,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('DCD', 0.2395),
      PlayerPositionShare('DCG', 0.1743),
      PlayerPositionShare('AG', 0.0963),
      PlayerPositionShare('DG', 0.0922),
      PlayerPositionShare('MOC', 0.0822),
      PlayerPositionShare('MDC', 0.0681),
    ],
  ),
  // Stéphane Fernandez — DCD 55%, DCG 38%, DC 7%
  '7fe67f9b-75c0-4606-8030-021b00900cc1': PlayerPositionProfile(
    displayName: 'Stéphane Fernandez',
    appearances: 119,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('DCD', 0.5489),
      PlayerPositionShare('DCG', 0.3773),
      PlayerPositionShare('DC', 0.0717),
    ],
  ),
  // Stéphane Manenti — DG 93%, AG 4%
  '665fcf3b-eace-4ae0-97a8-498f9bf918f5': PlayerPositionProfile(
    displayName: 'Stéphane Manenti',
    appearances: 71,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('DG', 0.9311),
      PlayerPositionShare('AG', 0.0411),
    ],
  ),
  // Thomas Blanchard — DG 52%, MG 16%, DD 16%, AG 14%
  'c0db4bc0-7725-4721-834b-0850e3c1e2a3': PlayerPositionProfile(
    displayName: 'Thomas Blanchard',
    appearances: 63,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('DG', 0.5192),
      PlayerPositionShare('MG', 0.1617),
      PlayerPositionShare('DD', 0.1554),
      PlayerPositionShare('AG', 0.1421),
    ],
  ),
  // Vincent Rouch — DD 71%, GB 29%
  '51a58cdb-30fa-4dce-8c30-c4957a7f8776': PlayerPositionProfile(
    displayName: 'Vincent Rouch',
    appearances: 4,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('DD', 0.7143),
      PlayerPositionShare('GB', 0.2857),
    ],
  ),
  // Xavier Grossin — GB 100%
  '35ad373d-fb20-482d-85e7-f7e7eaf93404': PlayerPositionProfile(
    displayName: 'Xavier Grossin',
    appearances: 3,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('GB', 1.0000),
    ],
  ),
  // Yoann Canal — AG 23%, BU 17%, AD 17%, BUD 17%, BUG 11%, MOC 10%
  'db3112de-05f3-43c9-aa0c-46a87a07d409': PlayerPositionProfile(
    displayName: 'Yoann Canal',
    appearances: 36,
    shares: <PlayerPositionShare>[
      PlayerPositionShare('AG', 0.2328),
      PlayerPositionShare('BU', 0.1712),
      PlayerPositionShare('AD', 0.1712),
      PlayerPositionShare('BUD', 0.1679),
      PlayerPositionShare('BUG', 0.1130),
      PlayerPositionShare('MOC', 0.0970),
    ],
  ),
};
