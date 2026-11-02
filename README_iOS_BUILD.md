# iOS release build (obfuscated)

> ⚠️ **ارفع الـ build على App Store Connect / TestFlight بس. ما تبعتوش للمراجعة (Submit for Review) غير بعد ما محمود يقول. فيه مراجعة شغالة دلوقتي على 3.0.0 (42).**

**Current version: 3.1.0 (51)** (from `pubspec.yaml`; `Info.plist` reads `FLUTTER_BUILD_NAME` / `FLUTTER_BUILD_NUMBER`). The build number must stay above the last uploaded iOS build (42).

### الجديد في 3.1.0 (51)
- قناة الأخبار (شاشة القناة، ألبوم صور، كارت في الرئيسية، إشعارات).
- طلب تغيير الكورس/الصف ومتابعة حالته.
- تقييم التطبيق جوا التطبيق (`in_app_review` — plugin جديد، `pod install` هيضيفه، مالوش إذن في Info.plist).
- إعدادات التطبيق من السيرفر (روابط/كروت/نصوص) — أي نص فيه سعر أو اشتراك أو دفع بيتشال على iOS.
- تحسين استرجاع التحميل بعد فشل الشبكة.

`ios/` ما اتغيرش عن 3.0.2 (نفس الـ signing و Info.plist و GoogleService-Info و PrivacyInfo). الـ obfuscation شغال زي ما هو (الأمر تحت).

## Command line (recommended)

```bash
flutter build ipa --release --obfuscate --split-debug-info=build/debug-info/ios
```

The `.ipa` lands in `build/ios/ipa/`. Upload it with Transporter or `xcrun altool`.

## Xcode Archive

Xcode's Archive doesn't pass the obfuscation flags by itself. Do one of these:

1. Run the command above first, then open `build/ios/archive/Runner.xcarchive` in Xcode (Window → Organizer) and distribute it from there. **Or**
2. Set the flags for Archive builds: in `ios/Flutter/Release.xcconfig` (or Runner → Build Settings → User-Defined) add
   ```
   DART_OBFUSCATION=true
   SPLIT_DEBUG_INFO=build/debug-info/ios
   ```
   then run `flutter build ios --release` once before archiving.

## Symbol files: keep them

`build/debug-info/ios` (and `build/debug-info/android` from `build_release.bat`) is **not** committed (it's in `.gitignore`). Keep a private copy for **every** released version. Without it, a crash stack trace from that version can't be read.

To read an obfuscated stack trace:

```bash
flutter symbolize -i crash.txt -d build/debug-info/ios/app.ios-arm64.symbols
```

## Do not change

Screen protection (`AppDelegate.swift`, `ScreenProtector`) is configured separately. Obfuscation doesn't affect it.
