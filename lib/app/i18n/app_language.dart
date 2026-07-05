enum AppLanguage {
  english('English', 'EN', 'Use English across the app.'),
  vietnamese('Tiếng Việt', 'VI', 'Sử dụng tiếng Việt trong ứng dụng.');

  final String label;
  final String code;
  final String description;

  const AppLanguage(this.label, this.code, this.description);
}
