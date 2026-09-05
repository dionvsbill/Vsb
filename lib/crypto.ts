import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto'

function key() {
  const raw = process.env.ENCRYPTION_KEY
  if (!raw) throw new Error('ENCRYPTION_KEY is not configured')
  const decoded = Buffer.from(raw, 'base64')
  if (decoded.length !== 32) throw new Error('ENCRYPTION_KEY must decode to exactly 32 bytes')
  return decoded
}

export function encryptSecret(value: string) {
  const iv = randomBytes(12)
  const cipher = createCipheriv('aes-256-gcm', key(), iv)
  const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()])
  const tag = cipher.getAuthTag()
  return Buffer.concat([iv, tag, ciphertext]).toString('base64')
}

export function decryptSecret(value: string) {
  const packed = Buffer.from(value, 'base64')
  if (packed.length < 29) throw new Error('Invalid encrypted secret')
  const decipher = createDecipheriv('aes-256-gcm', key(), packed.subarray(0, 12))
  decipher.setAuthTag(packed.subarray(12, 28))
  return Buffer.concat([decipher.update(packed.subarray(28)), decipher.final()]).toString('utf8')
}
