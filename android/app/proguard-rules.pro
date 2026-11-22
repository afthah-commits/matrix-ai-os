# Flutter and R8 Optimization Proguard Rules

# Keep Flutter wrapper and engine classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# ObjectBox and JNI rules
-dontwarn sun.misc.Unsafe
-dontwarn io.objectbox.**
-keepattributes *Annotation*
-keepclassmembers class * {
    @io.objectbox.annotation.Entity *;
}

# Flutter Secure Storage Keystore compatibility
-keep class androidx.security.crypto.** { *; }
