package com.prism.engine

import android.content.Context
import android.util.Base64
import java.security.KeyStore
import java.nio.ByteBuffer
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

internal class EncryptedNotificationPayload(@Suppress("UNUSED_PARAMETER") context: Context) {
    private val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
    private val key: SecretKey

    init {
        key = (keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.secretKey
            ?: KeyGenerator.getInstance("AES", ANDROID_KEY_STORE).apply {
                init(android.security.keystore.KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or
                        android.security.keystore.KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build())
            }.generateKey()
    }

    fun encrypt(value: String?): String? {
        if (value == null) return null
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(
            ByteBuffer.allocate(cipher.iv.size + encrypted.size)
                .put(cipher.iv)
                .put(encrypted)
                .array(),
            Base64.NO_WRAP,
        )
    }

    fun decrypt(value: String?): String? {
        if (value == null) return null
        val decoded = Base64.decode(value, Base64.NO_WRAP)
        val ivLength = 12
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
                Cipher.DECRYPT_MODE,
                key,
                javax.crypto.spec.GCMParameterSpec(128, decoded.copyOfRange(0, ivLength)),
        )
        return cipher.doFinal(decoded.copyOfRange(ivLength, decoded.size))
                .toString(Charsets.UTF_8)
    }

    companion object {
        private const val ANDROID_KEY_STORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "prism_notification_payload_v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
