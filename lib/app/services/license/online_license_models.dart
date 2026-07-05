class OnlineLicenseSession {
  final String email;
  final String accessToken;
  final String refreshToken;
  final DateTime authExpiresAt;
  final String deviceId;
  final String licenseKey;
  final DateTime licenseExpiresAt;
  final String? ownerEmail;
  final String? plan;
  final String? status;

  const OnlineLicenseSession({
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.authExpiresAt,
    required this.deviceId,
    required this.licenseKey,
    required this.licenseExpiresAt,
    this.ownerEmail,
    this.plan,
    this.status,
  });

  bool get isLicenseStillValid => licenseExpiresAt.isAfter(DateTime.now().toUtc());

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'auth_expires_at': authExpiresAt.toUtc().toIso8601String(),
      'device_id': deviceId,
      'license_key': licenseKey,
      'license_expires_at': licenseExpiresAt.toUtc().toIso8601String(),
      'owner_email': ownerEmail,
      'plan': plan,
      'status': status,
    };
  }

  OnlineLicenseSession copyWith({
    String? email,
    String? accessToken,
    String? refreshToken,
    DateTime? authExpiresAt,
    String? deviceId,
    String? licenseKey,
    DateTime? licenseExpiresAt,
    String? ownerEmail,
    String? plan,
    String? status,
  }) {
    return OnlineLicenseSession(
      email: email ?? this.email,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      authExpiresAt: authExpiresAt ?? this.authExpiresAt,
      deviceId: deviceId ?? this.deviceId,
      licenseKey: licenseKey ?? this.licenseKey,
      licenseExpiresAt: licenseExpiresAt ?? this.licenseExpiresAt,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      plan: plan ?? this.plan,
      status: status ?? this.status,
    );
  }

  static OnlineLicenseSession fromJson(Map<String, dynamic> json) {
    return OnlineLicenseSession(
      email: json['email'] as String? ?? '',
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      authExpiresAt: DateTime.parse(
        json['auth_expires_at'] as String,
      ).toUtc(),
      deviceId: json['device_id'] as String? ?? '',
      licenseKey: json['license_key'] as String? ?? '',
      licenseExpiresAt: DateTime.parse(
        json['license_expires_at'] as String,
      ).toUtc(),
      ownerEmail: json['owner_email'] as String?,
      plan: json['plan'] as String?,
      status: json['status'] as String?,
    );
  }
}

class OnlineLicenseStatus {
  final bool isLicensed;
  final bool requiresSignIn;
  final String message;
  final OnlineLicenseSession? session;

  const OnlineLicenseStatus({
    required this.isLicensed,
    required this.requiresSignIn,
    required this.message,
    this.session,
  });
}
