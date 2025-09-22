package com.example.outfitguardian.vault

import android.content.Context
import androidx.security.crypto.EncryptedFile
import androidx.security.crypto.MasterKey
import java.io.File
import java.io.InputStream

object PhotoVault {
  private const val VAULT_DIR = "vault"
  private const val META = "vault_meta.properties"

  private fun masterKey(ctx: Context) = MasterKey.Builder(ctx)
    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()

  private fun dir(ctx: Context): File = File(ctx.filesDir, VAULT_DIR).apply { mkdirs() }

  fun addImageEncrypted(ctx: Context, src: InputStream, filenameHint: String): File {
    val safe = filenameHint.replace(Regex("[^A-Za-z0-9._-]"), "_")
    val out = File(dir(ctx), "${System.currentTimeMillis()}_${safe}.bin")
    val ef = EncryptedFile.Builder(ctx, out, masterKey(ctx), EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB).build()
    ef.openFileOutput().use { dst -> src.copyTo(dst) }
    return out
  }

  /** Tresor-Inhalte sind während aktiver Session NICHT zugänglich. UI darf NICHT rendern. */
  fun listEncrypted(ctx: Context): List<File> = dir(ctx).listFiles()?.toList() ?: emptyList()

  /** Löschen nur zulässig, wenn Session NICHT aktiv (Business-Logik in aufrufender Ebene prüfen). */
  fun deleteAll(ctx: Context) {
    dir(ctx).listFiles()?.forEach { it.delete() }
  }
}
