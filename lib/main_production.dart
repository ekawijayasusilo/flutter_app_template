import 'package:flutter_app_template/app/app.dart';
import 'package:flutter_app_template/bootstrap.dart';
import 'package:flutter_app_template/firebase_options.dart';

Future<void> main() async {
  await bootstrap(
    firebaseOptions: DefaultFirebaseOptions.currentPlatform,
    builder: () => const App(),
  );
}
