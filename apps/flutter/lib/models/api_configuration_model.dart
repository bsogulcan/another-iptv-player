class ApiConfig {
  final String baseUrl;
  final String username;
  final String password;

  const ApiConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  Map<String, String> get baseParams => {
    'username': username,
    'password': password,
  };
}
