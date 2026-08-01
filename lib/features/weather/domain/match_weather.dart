class MatchWeatherHour {
  const MatchWeatherHour({
    required this.forecastAt,
    required this.label,
    this.temperature,
    this.apparentTemperature,
    this.precipitationProbability,
    this.weatherCode,
    this.windSpeed,
    this.windGusts,
    this.humidity,
  });

  final DateTime forecastAt;
  final String label;
  final double? temperature;
  final double? apparentTemperature;
  final int? precipitationProbability;
  final int? weatherCode;
  final double? windSpeed;
  final double? windGusts;
  final int? humidity;

  factory MatchWeatherHour.fromJson(Map<String, dynamic> json) {
    return MatchWeatherHour(
      forecastAt:
          DateTime.tryParse('${json['forecast_at'] ?? ''}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      label: (json['label'] ?? '').toString(),
      temperature: _double(json['temperature']),
      apparentTemperature: _double(json['apparent_temperature']),
      precipitationProbability: _int(json['precipitation_probability']),
      weatherCode: _int(json['weather_code']),
      windSpeed: _double(json['wind_speed']),
      windGusts: _double(json['wind_gusts']),
      humidity: _int(json['humidity']),
    );
  }
}

class MatchWeather {
  const MatchWeather({
    required this.matchId,
    required this.forecastFor,
    required this.latitude,
    required this.longitude,
    required this.geocodedAddress,
    required this.hourlyForecast,
    required this.fetchedAt,
    this.timezone,
    this.temperature,
    this.apparentTemperature,
    this.precipitationProbability,
    this.weatherCode,
    this.windSpeed,
    this.windGusts,
    this.humidity,
  });

  final String matchId;
  final DateTime forecastFor;
  final double latitude;
  final double longitude;
  final String geocodedAddress;
  final String? timezone;
  final double? temperature;
  final double? apparentTemperature;
  final int? precipitationProbability;
  final int? weatherCode;
  final double? windSpeed;
  final double? windGusts;
  final int? humidity;
  final List<MatchWeatherHour> hourlyForecast;
  final DateTime fetchedAt;

  factory MatchWeather.fromJson(Map<String, dynamic> json) {
    final rawHourly = json['hourly_forecast'];
    final hourly = rawHourly is List
        ? rawHourly
              .whereType<Map>()
              .map(
                (row) =>
                    MatchWeatherHour.fromJson(Map<String, dynamic>.from(row)),
              )
              .toList()
        : <MatchWeatherHour>[];

    return MatchWeather(
      matchId: (json['match_id'] ?? '').toString(),
      forecastFor:
          DateTime.tryParse('${json['forecast_for'] ?? ''}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      latitude: _double(json['latitude']) ?? 0,
      longitude: _double(json['longitude']) ?? 0,
      geocodedAddress: (json['geocoded_address'] ?? '').toString(),
      timezone: json['timezone']?.toString(),
      temperature: _double(json['temperature']),
      apparentTemperature: _double(json['apparent_temperature']),
      precipitationProbability: _int(json['precipitation_probability']),
      weatherCode: _int(json['weather_code']),
      windSpeed: _double(json['wind_speed']),
      windGusts: _double(json['wind_gusts']),
      humidity: _int(json['humidity']),
      hourlyForecast: hourly,
      fetchedAt:
          DateTime.tryParse('${json['fetched_at'] ?? ''}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

int? _int(Object? value) {
  if (value is num) return value.round();
  return int.tryParse('$value');
}
