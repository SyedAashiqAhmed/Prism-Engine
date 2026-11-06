package com.prism.engine

import android.database.Cursor
import java.util.Locale

internal object NotificationDeduplicator {
    fun findDuplicate(
        cursor: Cursor,
        merchant: String?,
        accountLast4: String?,
    ): Long? {
        val incomingMerchant = merchant.normalized()
        val incomingAccount = accountLast4.normalized()
        if (incomingMerchant == null && incomingAccount == null) return null

        while (cursor.moveToNext()) {
            val existingMerchant = cursor.getString(cursor.getColumnIndexOrThrow("merchant")).normalized()
            val existingAccount = cursor.getString(cursor.getColumnIndexOrThrow("account_last4")).normalized()
            if (hasMatchingIdentity(
                    incomingMerchant,
                    incomingAccount,
                    existingMerchant,
                    existingAccount,
                )
            ) {
                return cursor.getLong(cursor.getColumnIndexOrThrow("id"))
            }
        }
        return null
    }

    fun hasMatchingIdentity(
        incomingMerchant: String?,
        incomingAccount: String?,
        existingMerchant: String?,
        existingAccount: String?,
    ): Boolean {
        val merchantMatches = incomingMerchant.normalized() != null &&
            incomingMerchant.normalized() == existingMerchant.normalized()
        val accountMatches = incomingAccount.normalized() != null &&
            incomingAccount.normalized() == existingAccount.normalized()
        return merchantMatches || accountMatches
    }

    private fun String?.normalized(): String? =
        this?.trim()?.lowercase(Locale.ROOT)?.takeIf { it.isNotEmpty() }
}
