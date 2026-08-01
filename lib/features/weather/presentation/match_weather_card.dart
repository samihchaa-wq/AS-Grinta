import 'dart:math' as math;

import 'package:as_grinta/core/theme/app_theme.dart';
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
    final opensAt = kickoffAt.subtract(const Duration(days: 6));
    if (current.isBefore(opensAt) || !current.isBefore(kickoffAt)) {
      return const SizedBox.shrink();
    }

    final weather = ref.watch(matchWeatherProvider(matchId)).valueOrNull;
    if (weather == null ||
        !weather.forecastFor.isAtSameMomentAs(kickoffAt)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: _WeatherBody(
        weather: weather,
        kickoffAt: kickoffAt,
        plannedDurationMinutes: plannedDurationMinutes,
      ),
    );
  }
}

class _WeatherBody extends StatelessWidget {
  const _WeatherBody({
    required this.weather,
    required this.kickoffAt,
    required this.plannedDurationMinutes,
  });

  final MatchWeather weather;
  final DateTime kickoffAt;
  final int plannedDurationMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hourly = _relevantHours(weather.hourlyForecast, kickoffAt);
    final index = _grintaIndex(weather);
    final safety = _isDifficult(weather);
    final trend = _trend(weather.hourlyForecast, plannedDurationMinutes);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: AppTheme.primaryBright.withValues(alpha: .28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primary.withValues(alpha: .16),
                  ),
                  child: Icon(
                    _weatherIcon(weather.weatherCode),
                    color: AppTheme.primaryBright,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Météo du match',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Icon(
                            _weatherIcon(weather.weatherCode),
                            color: AppTheme.textPrimary,
                            size: 42,
                          ),
                          const SizedBox(width: 10),
                          if (weather.temperature case final temperature?)
                            Text(
                              '${_number(temperature)}°C',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _weatherLabel(weather.weatherCode),
                        style: const TextStyle(
                          color: AppTheme.primaryBright,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (weather.apparentTemperature case final apparent?) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Ressenti ${_number(apparent)}°C',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
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
            if (hourly.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(
                    color: AppTheme.outline.withValues(alpha: .35),
                  ),
                ),
                child: Row(
                  children: [
                    for (var index = 0; index < hourly.length; index++) ...[
                      if (index > 0)
                        Container(
                          width: 1,
                          height: 52,
                          color: AppTheme.outline.withValues(alpha: .35),
                        ),
                      Expanded(child: _HourlyCell(hour: hourly[index])),
                    ],
                  ],
                ),
              ),
            ],
            if (trend != null) ...[
              const SizedBox(height: 9),
              Text(
                trend,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: safety
                    ? theme.colorScheme.error.withValues(alpha: .08)
                    : AppTheme.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Row(
                children: [
                  Text(
                    'Indice Grinta ',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '$index/10',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: safety
                          ? theme.colorScheme.error
                          : AppTheme.primaryBright,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _grintaMessage(weather),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Prévision pour le lieu du match et l’heure du coup d’envoi',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textFaint,
                fontSize: 10.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Mis à jour à ${_time(weather.fetchedAt)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textFaint,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryBright),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textFaint,
                    fontSize: 10.5,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HourlyCell extends StatelessWidget {
  const _HourlyCell({required this.hour});

  final MatchWeatherHour hour;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          hour.label,
          style: const TextStyle(
            color: AppTheme.primaryBright,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Icon(_weatherIcon(hour.weatherCode), size: 18, color: AppTheme.textPrimary),
        const SizedBox(height: 2),
        Text(
          hour.temperature == null ? '—' : '${_number(hour.temperature!)}°',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        if (hour.precipitationProbability case final rain?)
          Text(
            '$rain %',
            style: const TextStyle(color: AppTheme.textFaint, fontSize: 10),
          ),
      ],
    );
  }
}

List<MatchWeatherHour> _relevantHours(
  List<MatchWeatherHour> hours,
  DateTime kickoffAt,
) {
  if (hours.length <= 3) return [...hours]..sort((a, b) => a.forecastAt.compareTo(b.forecastAt));
  final nearest = [...hours]
    ..sort((a, b) {
      final aDistance = a.forecastAt.difference(kickoffAt).inMinutes.abs();
      final bDistance = b.forecastAt.difference(kickoffAt).inMinutes.abs();
      return aDistance.compareTo(bDistance);
    });
  return nearest.take(3).toList()
    ..sort((a, b) => a.forecastAt.compareTo(b.forecastAt));
}

bool _isDifficult(MatchWeather weather) {
  final temp = weather.temperature;
  final gusts = weather.windGusts;
  final code = weather.weatherCode ?? -1;
  return (temp != null && (temp <= 1 || temp >= 34)) ||
      (gusts != null && gusts >= 60) ||
      code >= 95;
}

int _grintaIndex(MatchWeather weather) {
  if (_isDifficult(weather)) return 4;
  var score = 5;
  final rain = weather.precipitationProbability ?? 0;
  final temp = weather.temperature;
  final wind = weather.windSpeed ?? 0;
  if (rain >= 60) {
    score += 2;
  } else if (rain >= 25) {
    score += 1;
  }
  if (temp != null && temp >= 8 && temp <= 22) score += 1;
  if (wind >= 15 && wind <= 30) score += 1;
  return score.clamp(1, 10);
}

String _grintaMessage(MatchWeather weather) {
  if (_isDifficult(weather)) {
    return 'Conditions difficiles : prudence et consignes du staff.';
  }
  final code = weather.weatherCode ?? -1;
  if (_isRain(code) || (weather.precipitationProbability ?? 0) >= 55) {
    return 'Ça va glisser. Le vrai football commence.';
  }
  if ((weather.windSpeed ?? 0) >= 30) {
    return 'Aujourd’hui, même les centres ont leur propre GPS.';
  }
  if ((weather.temperature ?? 20) < 7) {
    return 'Les contrôles vont piquer un peu.';
  }
  if (code == 0 || code == 1) {
    return 'Conditions propres. Aucune excuse aujourd’hui.';
  }
  return 'Conditions de match validées.';
}

String? _trend(List<MatchWeatherHour> hours, int plannedDurationMinutes) {
  if (hours.length < 2) return null;
  final sorted = [...hours]..sort((a, b) => a.forecastAt.compareTo(b.forecastAt));
  final start = sorted.first;
  final end = sorted.last;
  final rainStart = start.precipitationProbability;
  final rainEnd = end.precipitationProbability;
  if (rainStart != null && rainEnd != null && rainEnd - rainStart >= 30) {
    return 'Pluie plus marquée prévue pendant la rencontre.';
  }
  final tempStart = start.temperature;
  final tempEnd = end.temperature;
  if (tempStart != null && tempEnd != null && (tempEnd - tempStart).abs() >= 4) {
    final direction = tempEnd < tempStart ? 'baisser' : 'monter';
    return 'La température devrait $direction nettement pendant le match.';
  }
  return null;
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

String _time(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
