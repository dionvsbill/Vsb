import { Ratelimit } from '@upstash/ratelimit'
import { Redis } from '@upstash/redis'

let redis: Redis | null = null
let limiters: Record<string, Ratelimit> = {}
function getRedis() {
  if (redis) return redis
  if (!process.env.UPSTASH_REDIS_REST_URL || !process.env.UPSTASH_REDIS_REST_TOKEN) return null
  redis = Redis.fromEnv()
  return redis
}
function limiter(name: string, requests: number, window: `${number} ${'s'|'m'|'h'}`) {
  const r = getRedis(); if (!r) return null
  return limiters[name] ||= new Ratelimit({ redis: r, limiter: Ratelimit.slidingWindow(requests, window), analytics: true, prefix: `vsbill:${name}` })
}
export async function enforceRateLimit(key: string, requests = 30, window: `${number} ${'s'|'m'|'h'}` = '1 m') {
  const l = limiter(`${requests}:${window}`, requests, window); if (!l) return { success: true, configured: false }
  return l.limit(key)
}
export const taskCompletionLimit = (key: string) => enforceRateLimit(`task-completion:${key}`, 5, '10 m')
export const paymentAttemptLimit = (key: string) => enforceRateLimit(`payment-attempt:${key}`, 3, '1 h')
