import { notFound, redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import ShopSectionClient from './ShopSectionClient'

const allowed=['products','jforce','customers','settings','orders','analytics']
export default async function ShopSection({params}:{params:{id:string;section:string}}){if(!allowed.includes(params.section))notFound();const s=await createClient();const {data:{user}}=await s.auth.getUser();if(!user)redirect('/login');const {data:shop}=await s.from('business_shops').select('id,name,store_slug,jforce_id,is_pro,delivery_fee,momo_number').eq('id',params.id).eq('user_id',user.id).single();if(!shop)notFound();const {data:products}=await s.from('inventory_products').select('id,name,selling_price,quantity,is_published,category').eq('shop_id',shop.id).order('created_at',{ascending:false});return <ShopSectionClient shop={shop} section={params.section} initialProducts={products||[]}/>
}
