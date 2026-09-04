import { Ratelimit } from '@upstash/ratelimit'
import { Redis } from '@upstash/redis'

let limiter: Ratelimit | null = null
export function getRateLimiter(){
 if(limiter)return limiter
 if(!process.env.UPSTASH_REDIS_REST_URL||!process.env.UPSTASH_REDIS_REST_TOKEN)return null
 const redis=Redis.fromEnv(); limiter=new Ratelimit({redis,limiter:Ratelimit.slidingWindow(30,'1 m'),analytics:true,prefix:'vsbil-tube-boost'})
 return limiter
}
export async function enforceRateLimit(key:string){const l=getRateLimiter();if(!l)return {success:true,configured:false};return l.limit(key)}
