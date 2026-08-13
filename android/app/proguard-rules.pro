# ML Kit text recognition ships one artifact per script. We only depend on the
# Latin recogniser, but the plugin's Java code references the Chinese, Devanagari,
# Japanese and Korean options classes, so R8 sees calls into classes that are not
# on the classpath. Silence those references rather than pulling in ~10 MB of
# models the app never asks for.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
