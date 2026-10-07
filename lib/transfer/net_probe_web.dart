// Browsers cannot resolve names directly; their own online flag is accurate, so trust it.
Future<bool> hostResolves(String host, Duration timeout) async => false;
