# Optional ML Kit text recognisers the app doesn't use.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ONNX Runtime (auto-crop's page model) is called from native code by name.
-keep class ai.onnxruntime.** { *; }

# ML Kit looks its components up by name: keep them whole in release builds.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google_mlkit_document_scanner.** { *; }
-keep class com.google_mlkit_commons.** { *; }
