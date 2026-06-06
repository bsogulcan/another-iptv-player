import 'dart:async';

class PlayerErrorHandler {
  Timer? _errorTimer;
  int _retryCount = 0;
  static const int _maxRetryCount = 5;
  static const int _baseDelayMs = 1000; // 1 saniye başlangıç

  void handleError(String error, Function() onRetry, Function(String) showSnackBar) {
    _errorTimer?.cancel();

    // Exponential backoff (1s, 2s, 4s, 8s, 16s)
    int delayMs = (_baseDelayMs * (1 << _retryCount)).clamp(1000, 30000);

    print('PLAYER ERROR -> $error (Retry: $_retryCount, Delay: ${delayMs}ms)');

    if (error.contains('Failed to open') && _retryCount < _maxRetryCount) {
      _errorTimer = Timer(Duration(milliseconds: delayMs), () {
        _retryCount++;
        onRetry();
      });
    } else {
      showSnackBar(error);
    }
  }

  void reset() {
    _errorTimer?.cancel();
    _retryCount = 0;
  }
}