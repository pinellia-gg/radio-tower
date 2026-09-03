import 'package:flutter/material.dart';
import 'package:radio_tower/manger/ConfigKeys.dart';
import 'package:radio_tower/manger/ConfigMgr.dart';

class AppLocaleProvider extends ChangeNotifier {
  static const Locale defaultLocale = Locale('en');
  static const List<Locale> supportedLocales = [defaultLocale, Locale('zh')];

  Locale _locale = defaultLocale;

  Locale get locale => _locale;

  Future<void> load() async {
    final storedLanguageCode = ConfigMgr().getStringVal(
      ConfigKeys.KEY_APP_LANGUAGE,
      defaultLocale.languageCode,
    );
    final storedLocale = _localeForLanguageCode(storedLanguageCode);
    if (_locale == storedLocale) {
      return;
    }
    _locale = storedLocale;
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    final nextLocale = _localeForLanguageCode(locale.languageCode);
    if (_locale == nextLocale) {
      return;
    }
    _locale = nextLocale;
    ConfigMgr()
        .put(ConfigKeys.KEY_APP_LANGUAGE, nextLocale.languageCode)
        .save();
    notifyListeners();
  }

  Locale _localeForLanguageCode(String languageCode) {
    for (final locale in supportedLocales) {
      if (locale.languageCode == languageCode) {
        return locale;
      }
    }
    return defaultLocale;
  }
}
