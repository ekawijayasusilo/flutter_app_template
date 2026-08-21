import 'package:flutter_app_template/app/app.dart';
import 'package:flutter_app_template/bootstrap.dart';

Future<void> main() async {
  await bootstrap(() => const App());
}
