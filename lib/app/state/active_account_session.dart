class ActiveAccountSession {
  static int? activeAccountId;
  static String? activeAccountLogin;

  static int get accountId => activeAccountId ?? 1;

  static void useMt5Account({required int id, String? login}) {
    activeAccountId = id;
    activeAccountLogin = login;
  }
}
