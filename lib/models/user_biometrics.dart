/// A snapshot of the user's most recently recorded biometric readings.
/// Values are stored as strings so the UI can decide how to format them.
class UserBiometrics {
  final String bodyTemperature;
  final String bloodPressure;
  final String heartRate;
  final String oxygenLevel;
  final String weight;
  final String height;
  final DateTime? recordedAt;

  const UserBiometrics({
    this.bodyTemperature = '--',
    this.bloodPressure = '--/--',
    this.heartRate = '--',
    this.oxygenLevel = '98%',
    this.weight = '--',
    this.height = '--',
    this.recordedAt,
  });

  UserBiometrics copyWith({
    String? bodyTemperature,
    String? bloodPressure,
    String? heartRate,
    String? oxygenLevel,
    String? weight,
    String? height,
    DateTime? recordedAt,
  }) {
    return UserBiometrics(
      bodyTemperature: bodyTemperature ?? this.bodyTemperature,
      bloodPressure: bloodPressure ?? this.bloodPressure,
      heartRate: heartRate ?? this.heartRate,
      oxygenLevel: oxygenLevel ?? this.oxygenLevel,
      weight: weight ?? this.weight,
      height: height ?? this.height,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bodyTemperature': bodyTemperature,
      'bloodPressure': bloodPressure,
      'heartRate': heartRate,
      'oxygenLevel': oxygenLevel,
      'weight': weight,
      'height': height,
      'recordedAt': recordedAt?.toIso8601String(),
    };
  }

  factory UserBiometrics.fromMap(Map<dynamic, dynamic> map) {
    return UserBiometrics(
      bodyTemperature: map['bodyTemperature']?.toString() ?? '--',
      bloodPressure: map['bloodPressure']?.toString() ?? '--/--',
      heartRate: map['heartRate']?.toString() ?? '--',
      oxygenLevel: map['oxygenLevel']?.toString() ?? '98%',
      weight: map['weight']?.toString() ?? '--',
      height: map['height']?.toString() ?? '--',
      recordedAt: map['recordedAt'] != null
          ? DateTime.tryParse(map['recordedAt'].toString())
          : null,
    );
  }
}
