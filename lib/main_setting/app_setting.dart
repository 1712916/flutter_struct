import 'package:easy_localization/easy_localization.dart';
import 'package:mp3_convert/di/di.dart';
import 'package:mp3_convert/util/downloader_util.dart';

class AppSetting {
  Future initApp() async {
    return Future.wait([
      //init locale language
      EasyLocalization.ensureInitialized(),

      Future(() => registerDI()),
    ]);
  }
}
