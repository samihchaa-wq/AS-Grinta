import 'package:as_grinta/features/weather/data/match_weather_repository.dart';
import 'package:as_grinta/features/weather/domain/match_weather.dart';
import 'package:as_grinta/features/weather/presentation/match_weather_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWeatherRepository implements MatchWeatherRepository {
  _FakeWeatherRepository(this.weather);

  final MatchWeather? weather;
  int watchCount = 0;

  @override
  Stream<MatchWeather?> watchMatchWeather(String matchId) {
    watchCount += 1;
    return Stream<MatchWeather?>.value(weather);
  }
}

MatchWeather _weather({
  required DateTime kickoff,
  int weatherCode = 61,
  double? temperature = 16,
  double? apparentTemperature = 14,
  int? rain = 65,
  double? wind = 22,
  double? gusts = 35,
  int? humidity = 78,
  List<MatchWeatherHour>? hours,
}) {
  return MatchWeather(
    matchId: 'match-1',
    forecastFor: kickoff,
    latitude: 43.6045,
    longitude: 1.444,
    geocodedAddress: '1 rue du Stade, 31000 Toulouse',
    timezone: 'Europe/Paris',
    temperature: temperature,
    apparentTemperature: apparentTemperature,
    precipitationProbability: rain,
    weatherCode: weatherCode,
    windSpeed: wind,
    windGusts: gusts,
    humidity: humidity,
    hourlyForecast: hours ??
        [
          MatchWeatherHour(
            forecastAt: kickoff.subtract(const Duration(hours: 1)),
            label: '19h',
            temperature: 17,
            precipitationProbability: 60,
            weatherCode: 61,
          ),
          MatchWeatherHour(
            forecastAt: kickoff,
            label: '20h',
            temperature: 16,
            precipitationProbability: 65,
            weatherCode: 61,
          ),
          MatchWeatherHour(
            forecastAt: kickoff.add(const Duration(hours: 1)),
            label: '21h',
            temperature: 15,
            precipitationProbability: 70,
            weatherCode: 61,
          ),
        ],
    fetchedAt: kickoff.subtract(const Duration(hours: 2)),
  );
}

Widget _app({
  required _FakeWeatherRepository repository,
  required DateTime kickoff,
  required DateTime now,
}) {
  return ProviderScope(
    overrides: [matchWeatherRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MatchWeatherCard(
            matchId: 'match-1',
            kickoffAt: kickoff,
            plannedDurationMinutes: 90,
            now: now,
          ),
        ),
      ),
    ),
  );
}

void main() {
  final kickoff = DateTime(2040, 1, 7, 20);

  testWidgets('la carte reste invisible avant J-6', (tester) async {
    final repository = _FakeWeatherRepository(_weather(kickoff: kickoff));
    await tester.pumpWidget(
      _app(
        repository: repository,
        kickoff: kickoff,
        now: kickoff.subtract(const Duration(days: 6, minutes: 1)),
      ),
    );
    await tester.pump();

    expect(find.text('Météo du match'), findsNothing);
    expect(repository.watchCount, 0);
  });

  testWidgets('la carte apparaît exactement à J-6 avec les données', (
    tester,
  ) async {
    final repository = _FakeWeatherRepository(_weather(kickoff: kickoff));
    await tester.pumpWidget(
      _app(
        repository: repository,
        kickoff: kickoff,
        now: kickoff.subtract(const Duration(days: 6)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Météo du match'), findsOneWidget);
    expect(find.text('16°C'), findsOneWidget);
    expect(find.text('Ressenti 14°C'), findsOneWidget);
    expect(find.text('Pluie'), findsWidgets);
  });

  testWidgets('les trois créneaux horaires sont affichés', (tester) async {
    final repository = _FakeWeatherRepository(_weather(kickoff: kickoff));
    await tester.pumpWidget(
      _app(
        repository: repository,
        kickoff: kickoff,
        now: kickoff.subtract(const Duration(days: 2)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('19h'), findsOneWidget);
    expect(find.text('20h'), findsOneWidget);
    expect(find.text('21h'), findsOneWidget);
  });

  testWidgets(
    'les données optionnelles manquantes ne font pas crasher la carte',
    (tester) async {
      final repository = _FakeWeatherRepository(
        _weather(
          kickoff: kickoff,
          temperature: null,
          apparentTemperature: null,
          rain: null,
          wind: null,
          gusts: null,
          humidity: null,
          hours: const [],
        ),
      );
      await tester.pumpWidget(
        _app(
          repository: repository,
          kickoff: kickoff,
          now: kickoff.subtract(const Duration(days: 1)),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Météo du match'), findsOneWidget);
      expect(find.textContaining('Indice Grinta'), findsOneWidget);
    },
  );

  testWidgets('une prévision liée à une ancienne heure est masquée', (
    tester,
  ) async {
    final repository = _FakeWeatherRepository(
      _weather(kickoff: kickoff.subtract(const Duration(hours: 1))),
    );
    await tester.pumpWidget(
      _app(
        repository: repository,
        kickoff: kickoff,
        now: kickoff.subtract(const Duration(days: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Météo du match'), findsNothing);
  });

  testWidgets('les conditions difficiles utilisent un message de prudence', (
    tester,
  ) async {
    final repository = _FakeWeatherRepository(
      _weather(kickoff: kickoff, weatherCode: 95, gusts: 70),
    );
    await tester.pumpWidget(
      _app(
        repository: repository,
        kickoff: kickoff,
        now: kickoff.subtract(const Duration(hours: 4)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('prudence'), findsOneWidget);
    expect(find.text('4/10'), findsOneWidget);
  });

  testWidgets('une pluie marquée produit la signature Grinta', (tester) async {
    final repository = _FakeWeatherRepository(_weather(kickoff: kickoff));
    await tester.pumpWidget(
      _app(
        repository: repository,
        kickoff: kickoff,
        now: kickoff.subtract(const Duration(days: 3)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Ça va glisser. Le vrai football commence.'),
      findsOneWidget,
    );
  });

  testWidgets('aucun cache météo ne laisse simplement la carte absente', (
    tester,
  ) async {
    final repository = _FakeWeatherRepository(null);
    await tester.pumpWidget(
      _app(
        repository: repository,
        kickoff: kickoff,
        now: kickoff.subtract(const Duration(days: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Météo du match'), findsNothing);
  });
}
