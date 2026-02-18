class ApiConstants {
  const ApiConstants._();

  static const String baseUrl = 'https://socket.eldor.kz';

  static const String apiToken = '';

  static const String loginPath = '/api/auth/login';
  static const String chatsPath = '/api/chats';
  static const String startChatPath = '/api/chats/start';

  static String uploadPath(String kind) => '/api/files/upload-$kind';
}
