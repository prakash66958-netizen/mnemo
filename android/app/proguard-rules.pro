# Mnemo ProGuard / R8 rules.
#
# google_mlkit_text_recognition bundles optional language-specific recognizer
# modules (Chinese, Devanagari, Japanese, Korean) that are only loaded at
# runtime when present. We don't ship those extra models, so R8's strict
# reference check fails. Ignore the missing classes — the runtime
# `NoClassDefFoundError` is already caught by the plugin.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-keep class com.google.mlkit.vision.text.chinese.** { *; }
-keep class com.google.mlkit.vision.text.devanagari.** { *; }
-keep class com.google.mlkit.vision.text.japanese.** { *; }
-keep class com.google.mlkit.vision.text.korean.** { *; }

# Keep Isar native-lookup classes — R8 can't see through the FFI bindings.
-keep class dev.isar.** { *; }
-dontwarn dev.isar.**

# flutter_local_notifications uses reflection to instantiate the serializer
# for its notification schedule. Keep Gson-annotated fields.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.dexterous.** { *; }
