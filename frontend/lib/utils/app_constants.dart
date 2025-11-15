class AppConstants {
  // The base URL for your backend API. Use 'http://10.0.2.2:3000/api' for Android emulator,
  // or your actual server IP for real devices (e.g., 'http://192.168.x.x:3000/api').
  static const String BASE_API_URL = 'http://10.0.2.2:3000/api';

  // The MQTT broker host. Use 'broker.hivemq.com' for public testing,
  // or your own broker address for production.
  static const String MQTT_BROKER_HOST = 'broker.hivemq.com';

  // The MQTT topic for sending lock commands to the smart locker.
  static const String MQTT_LOCK_TOPIC = 'smartlocker/control/lock';
}
