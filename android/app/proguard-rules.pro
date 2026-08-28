# Firebase discovers its components by reading registrar class names out of the
# manifest and calling the no-arg constructor reflectively. R8 sees no caller for
# those constructors and removes them, so every ML Kit registrar failed with
# NoSuchMethodException at startup and text recognition silently never registered.
# The app still launched, which is what made this easy to miss.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}

# ML Kit text recognition ships one artifact per script. We only depend on the
# Latin recogniser, but the plugin's Java code references the Chinese, Devanagari,
# Japanese and Korean options classes, so R8 sees calls into classes that are not
# on the classpath. Silence those references rather than pulling in ~10 MB of
# models the app never asks for.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
