import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import ShopClient from './ShopClient'

export default async function ShopPage({params}:{params:{slug:string}}){
 const s=await createClient(); const {data:shop}=await s.from('business_shops').select('id,name,description,logo_url,banner_url,delivery_fee,is_published,shop_status').eq('store_slug',params.slug).maybeSingle();
 if(!shop||!shop.is_published||shop.shop_status!=='approved')notFound();
 const {data:products}=await s.from('inventory_products').select('id,name,selling_price,description,image_url,category').eq('shop_id',shop.id).eq('is_published',true).gt('quantity',0).order('created_at',{ascending:false});
 return <main className="min-h-screen bg-slate-50 dark:bg-slate-950">{shop.banner_url&&<img src={shop.banner_url} alt="" className="h-52 w-full object-cover"/>}<header className="mx-auto max-w-7xl px-4 py-8"><div className="flex items-center gap-4">{shop.logo_url?<img src={shop.logo_url} alt="" className="h-16 w-16 rounded-2xl object-cover"/>:<div className="h-16 w-16 rounded-2xl bg-slate-900"/>}<div><h1 className="text-3xl font-black">{shop.name}</h1><p className="mt-1 text-slate-500">{shop.description||'Welcome to our store.'}</p></div></div></header><ShopClient products={products||[]} deliveryFee={Number(shop.delivery_fee||0)} shopName={shop.name} shopId={shop.id}/></main>
}
