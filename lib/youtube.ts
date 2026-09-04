export function parseVideoId(input: string) {
  try { const url=new URL(input); if(url.hostname==='youtu.be') return url.pathname.slice(1).split('/')[0] || null; if(url.hostname.endsWith('youtube.com')) return url.searchParams.get('v') || (url.pathname.startsWith('/shorts/') ? url.pathname.split('/')[2] : null) } catch {}
  return null
}

export async function getVideo(videoId:string){
 const key=process.env.YOUTUBE_API_KEY; if(!key) throw new Error('YOUTUBE_API_KEY is not configured')
 const r=await fetch(`https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails,status&id=${encodeURIComponent(videoId)}&key=${encodeURIComponent(key)}`,{cache:'no-store'})
 const d=await r.json(); if(!r.ok) throw new Error(d?.error?.message||'YouTube API request failed'); const item=d.items?.[0]; if(!item) throw new Error('YouTube video not found')
 return {id:item.id,title:item.snippet.title,thumbnail:item.snippet.thumbnails?.high?.url||item.snippet.thumbnails?.default?.url||null,channelId:item.snippet.channelId,duration:item.contentDetails.duration}
}

export function isoDurationSeconds(value:string){const m=value.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);if(!m)return 0;return Number(m[1]||0)*3600+Number(m[2]||0)*60+Number(m[3]||0)}
