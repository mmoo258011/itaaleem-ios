# iOS release build (obfuscated)

**Current version: 3.2.0 (52)** (from `pubspec.yaml`; `Info.plist` reads `FLUTTER_BUILD_NAME` / `FLUTTER_BUILD_NUMBER`). The build number must stay above the last uploaded iOS build (51).

### الجديد في 3.2.0 (52)
- الواجهة الذكية (WebView) للطالب، و«لوحة التحكم» لأدمن المركز (بتظهر بس لو السيرفر رجّع `panel_handoff_enabled`).
- «تحديث» بيعيد نفس الصفحة في مكانها، ولينكات السوشيال بتاعة المدرس بتفتح بره التطبيق.
- تحميل نفس الدرس مرتين بقى شغال (باج UNIQUE اتصلح).
- الأمان: تسجيل الخروج بيمسح الـ cache والـ storage بتوع الـ WebView، والـ token بيتبعت لـ API بتاعنا بس، والملفات اللي بتتفتح من لينك بتفضل جوه الـ temp.
- **iOS (Swift جديد):** فولدر الدروس المتحمّلة (`offline_videos`) واخد `isExcludedFromBackup` من خلال channel `com.itaaleem.app/storage` في `AppDelegate.swift`، عشان ميتعملوش backup على iCloud.
- `PrivacyInfo.xcprivacy` اتحدّث بالبيانات الجديدة، وشاشة الإطلاق بقت بيضا (صور الـ Dark اتشالت).
- مفيش أي دفع جوه التطبيق (`smartPaymentsEnabled = false`)، وفلتر الأسعار على iOS زي ما هو.

### الجديد في 3.1.0 (51)
- قناة الأخبار (شاشة القناة، ألبوم صور، كارت في الرئيسية، إشعارات).
- طلب تغيير الكورس/الصف ومتابعة حالته.
- تقييم التطبيق جوا التطبيق (`in_app_review` — plugin جديد، `pod install` هيضيفه، مالوش إذن في Info.plist).
- إعدادات التطبيق من السيرفر (روابط/كروت/نصوص) — أي نص فيه سعر أو اشتراك أو دفع بيتشال على iOS.
- iOS: مفيش أي سعر أو «اشتراك» أو «ادفع» — شيت المادة المقفولة بقى «فعّل المادة» و«تواصل مع المركز» بس، وبوستات الأخبار اللي فيها سعر أو دفع مش بتظهر.
- تحسين استرجاع التحميل بعد فشل الشبكة.

`ios/` في 3.2.0: اتغيّر `AppDelegate.swift` و `PrivacyInfo.xcprivacy` وشاشة الإطلاق. الـ signing و `Info.plist` و `GoogleService-Info` زي ما هما. الـ obfuscation شغال زي ما هو (الأمر تحت).

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
