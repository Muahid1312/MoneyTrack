package com.moneytrack.moneytrack

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class SecurityBridge(private val activity: FlutterFragmentActivity) {
    private val prefs = activity.getSharedPreferences("moneytrack_secure", 0)
    private val store: KeyStore get() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private val verifierAlias = "moneytrack.verifier.v1"
    private val bioAlias = "moneytrack.biometric.v1"
    private var prompting = false
    private fun key(alias: String, biometric: Boolean, create: Boolean): SecretKey {
        val existing = store.getKey(alias, null) as? SecretKey
        if (existing != null) return existing
        if (!create) throw IllegalStateException("Device security key unavailable")
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).setRandomizedEncryptionRequired(true)
            if (biometric) {
                spec.setUserAuthenticationRequired(true).setUserAuthenticationValidityDurationSeconds(-1)
                if (android.os.Build.VERSION.SDK_INT >= 24) spec.setInvalidatedByBiometricEnrollment(true)
            }
            init(spec.build()); generateKey()
        }
    }
    private fun clearBio() { if (store.containsAlias(bioAlias)) store.deleteEntry(bioAlias); prefs.edit().remove("bio").commit() }
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "moneytrack/security").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "privacyReady" -> { val cover = activity.window.decorView.foreground; activity.window.decorView.postOnAnimationDelayed({ if (activity.hasWindowFocus() && activity.window.decorView.foreground === cover) activity.window.decorView.foreground = null }, 32); result.success(null) }
                    "read" -> {
                        val raw = prefs.getString("lock", null)
                        if (raw == null) result.success(null) else {
                            val obj = JSONObject(raw)
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.DECRYPT_MODE, key(verifierAlias, false, false), GCMParameterSpec(128, Base64.decode(obj.getString("iv"), Base64.NO_WRAP)))
                            result.success(String(cipher.doFinal(Base64.decode(obj.getString("data"), Base64.NO_WRAP)), Charsets.UTF_8))
                        }
                    }
                    "write" -> {
                        val value = call.arguments as? String
                        if (value == null) {
                            if (!prefs.edit().remove("lock").commit()) throw IllegalStateException("Secure storage write failed")
                            clearBio()
                        } else {
                            val config = JSONObject(value)
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.ENCRYPT_MODE, key(verifierAlias, false, true))
                            val obj = JSONObject().put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
                                .put("data", Base64.encodeToString(cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP))
                            if (!prefs.edit().putString("lock", obj.toString()).commit()) throw IllegalStateException("Secure storage write failed")
                            if (!config.optBoolean("biometric")) clearBio()
                        }
                        result.success(null)
                    }
                    "enroll", "authenticate" -> prompt(call.method == "enroll", result)
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("DEVICE_SECURITY", "Device-backed security is unavailable; use your app PIN", null) }
        }
    }
    private fun prompt(enroll: Boolean, result: MethodChannel.Result) {
        if (prompting || BiometricManager.from(activity).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) != BiometricManager.BIOMETRIC_SUCCESS) { result.success(false); return }
        try {
            if (enroll) clearBio()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val saved = if (enroll) null else JSONObject(prefs.getString("bio", null) ?: run { result.success(false); return })
            if (enroll) cipher.init(Cipher.ENCRYPT_MODE, key(bioAlias, true, true))
            else cipher.init(Cipher.DECRYPT_MODE, key(bioAlias, true, false), GCMParameterSpec(128, Base64.decode(saved!!.getString("iv"), Base64.NO_WRAP)))
            prompting = true
            val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationError(code: Int, message: CharSequence) { prompting = false; result.success(false) }
                override fun onAuthenticationSucceeded(authentication: BiometricPrompt.AuthenticationResult) {
                    prompting = false
                    try {
                        val authenticated = authentication.cryptoObject?.cipher ?: throw IllegalStateException()
                        if (enroll) {
                            val token = authenticated.doFinal("moneytrack-unlock-v1".toByteArray(Charsets.UTF_8))
                            val obj = JSONObject().put("iv", Base64.encodeToString(authenticated.iv, Base64.NO_WRAP)).put("data", Base64.encodeToString(token, Base64.NO_WRAP))
                            if (!prefs.edit().putString("bio", obj.toString()).commit()) throw IllegalStateException()
                            result.success(true)
                        } else result.success(String(authenticated.doFinal(Base64.decode(saved!!.getString("data"), Base64.NO_WRAP)), Charsets.UTF_8) == "moneytrack-unlock-v1")
                    } catch (_: Exception) { result.success(false) }
                }
            })
            val info = BiometricPrompt.PromptInfo.Builder().setTitle(if (enroll) "Enable MoneyTrack biometrics" else "Unlock MoneyTrack")
                .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG).setNegativeButtonText("Use app PIN").build()
            prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
        } catch (_: Exception) { prompting = false; result.success(false) }
    }
}
