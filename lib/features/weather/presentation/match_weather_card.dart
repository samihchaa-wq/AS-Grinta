import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/features/weather/data/match_weather_repository.dart';
import 'package:as_grinta/features/weather/domain/match_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchWeatherCard extends ConsumerWidget {
  const MatchWeatherCard({
    required this.matchId,
    required this.kickoffAt,
    required this.plannedDurationMinutes,
    this.now,
    super.key,
  });

  final String matchId;
  final DateTime kickoffAt;
  final int plannedDurationMinutes;

  /// Injection uniquement utile aux tests : en production l'heure du terminal
  /// sert seulement à décider si la carte J-6 doit être visible. Le serveur
  /// reste la source de vérité pour les appels météo et leur cadence.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = now ?? DateTime.now();
    final opensAt = matchFeaturesOpenAt(kickoffAt);
    if (current.isBefore(opensAt) || !current.isBefore(kickoffAt)) {
      return const SizedBox.shrink();
    }

    final weather = ref.watch(matchWeatherProvider(matchId)).valueOrNull;
    if (weather == null || !weather.forecastFor.isAtSameMomentAs(kickoffAt)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: _WeatherBody(weather: weather),
    );
  }
}

class _WeatherBody extends StatelessWidget {
  const _WeatherBody({required this.weather});

  final MatchWeather weather;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: AppTheme.primaryBright.withValues(alpha: .28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primary.withValues(alpha: .16),
                  ),
                  child: Icon(
                    _weatherIcon(weather.weatherCode),
                    color: AppTheme.primaryBright,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Météo au coup d’envoi',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _weatherIcon(weather.weatherCode),
                            color: AppTheme.textPrimary,
                            size: 36,
                          ),
                          const SizedBox(width: 8),
                          if (weather.temperature case final temperature?)
                            Flexible(
                              child: Text(
                                '${_number(temperature)}°C',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _weatherLabel(weather.weatherCode),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.primaryBright,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      if (weather.apparentTemperature case final apparent?) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Ressenti ${_number(apparent)}°C',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      if (weather.precipitationProbability case final rain?)
                        _Metric(
                          icon: Icons.water_drop_outlined,
                          label: 'Pluie',
                          value: '$rain %',
                        ),
                      if (weather.windSpeed case final wind?)
                        _Metric(
                          icon: Icons.air_rounded,
                          label: 'Vent',
                          value: '${_number(wind)} km/h',
                        ),
                      if (weather.humidity case final humidity?)
                        _Metric(
                          icon: Icons.opacity_rounded,
                          label: 'Humidité',
                          value: '$humidity %',
                        ),
                      if (weather.windGusts case final gusts?)
                        _Metric(
                          icon: Icons.speed_rounded,
                          label: 'Rafales',
                          value: '${_number(gusts)} km/h',
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.primaryBright),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textFaint, fontSize: 10.5),
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _weatherIcon(int? code) {
  if (code == null) return Icons.cloud_outlined;
  if (code == 0 || code == 1) return Icons.wb_sunny_outlined;
  if (code == 2 || code == 3) return Icons.cloud_outlined;
  if (code == 45 || code == 48) return Icons.foggy;
  if (_isRain(code)) return Icons.grain_rounded;
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
    return Icons.ac_unit_rounded;
  }
  if (code >= 95) return Icons.thunderstorm_outlined;
  return Icons.cloud_outlined;
}

String _weatherLabel(int? code) {
  if (code == null) return 'Prévisions disponibles';
  if (code == 0) return 'Ciel dégagé';
  if (code == 1) return 'Peu nuageux';
  if (code == 2) return 'Partiellement nuageux';
  if (code == 3) return 'Couvert';
  if (code == 45 || code == 48) return 'Brouillard';
  if (code >= 51 && code <= 57) return 'Bruine';
  if (code >= 61 && code <= 67) return 'Pluie';
  if (code >= 71 && code <= 77) return 'Neige';
  if (code >= 80 && code <= 82) return 'Averses';
  if (code == 85 || code == 86) return 'Averses de neige';
  if (code >= 95) return 'Orage';
  return 'Conditions variables';
}

bool _isRain(int code) =>
    (code >= 51 && code <= 67) || (code >= 80 && code <= 82);

String _number(double value) {
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < .05) return rounded.toInt().toString();
  return value.toStringAsFixed(1).replaceAll('.', ',');
}
