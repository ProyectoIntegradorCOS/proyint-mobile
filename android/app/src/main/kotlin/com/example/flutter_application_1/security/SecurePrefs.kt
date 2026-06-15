package com.example.flutter_application_1.security

import android.content.Context
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

object SecurePrefs {
    private const val TAG = "SecurePrefs"
    private const val FILE_NAME = "thaqhiri_secure_prefs"
    private const val KEY_AUTH_TOKEN = "auth_token"

    private fun prefs(context: Context) = EncryptedSharedPreferences.create(
        context,
        FILE_NAME,
        MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    fun setAuthToken(context: Context, token: String) {
        prefs(context).edit().putString(KEY_AUTH_TOKEN, token).apply()
        Log.i(TAG, "Token escrito en EncryptedSharedPreferences OK")
    }

    fun clearAuthToken(context: Context) {
        prefs(context).edit().remove(KEY_AUTH_TOKEN).apply()
        Log.i(TAG, "Token eliminado de EncryptedSharedPreferences")
    }

    fun getAuthToken(context: Context): String? =
        prefs(context).getString(KEY_AUTH_TOKEN, null)
}
