# Optional ML Kit text recognisers the app doesn't use.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ONNX Runtime (auto-crop's page model) is called from native code by name.
-keep class ai.onnxruntime.** { *; }
