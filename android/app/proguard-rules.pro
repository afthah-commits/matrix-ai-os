# Flutter and R8 Optimization Proguard Rules

# Keep Flutter wrapper and engine classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep App Native MethodChannels, Services & Kotlin Bridges
-keep class com.matrixai.os.matrix_ai_os.** { *; }

# ObjectBox and JNI rules
-dontwarn sun.misc.Unsafe
-dontwarn io.objectbox.**
-keepattributes *Annotation*
-keep class io.objectbox.** { *; }
-keepclassmembers class * {
    @io.objectbox.annotation.Entity *;
}

# Flutter Secure Storage Keystore compatibility
-keep class androidx.security.crypto.** { *; }

# WorkManager background sync
-keep class androidx.work.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }

# Google ML Kit Text Recognition
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**

# Speech to Text and Flutter TTS Native Bridges
-keep class com.csdcorp.speech_to_text.** { *; }
-keep class com.tundralabs.fluttertts.** { *; }
-keep class com.fluttertts.** { *; }
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Suppress Google Play Core warnings for deferred components in Flutter
-dontwarn com.google.android.play.core.**
