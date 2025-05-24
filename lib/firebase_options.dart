import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return const FirebaseOptions(
      apiKey: 'YOUR_API_KEY',
      appId: '1:YOUR_APP_ID:web:random',
      messagingSenderId: 'YOUR_SENDER_ID',
      projectId: 'videotv-fc3b9',
      databaseURL: 'https://videotv-fc3b9-default-rtdb.firebaseio.com/',
    );
  }
}
