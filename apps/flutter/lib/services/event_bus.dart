import 'package:rxdart/rxdart.dart';

class EventBus {
  static final _instance = EventBus._internal();
  factory EventBus() => _instance;
  EventBus._internal();

  final _eventController = PublishSubject<Map<String, dynamic>>();

  void emit(String eventName, dynamic data) {
    _eventController.add({'event': eventName, 'data': data});
  }

  Stream<T> on<T>(String eventName) {
    return _eventController.stream
        .where((event) => event['event'] == eventName)
        .map((event) => event['data'] as T);
  }

  void dispose() {
    _eventController.close();
  }
}
