import { createClient } from '@/lib/supabase/server';
import { Band } from '@/lib/types';

export async function getUserBands(): Promise<Band[]> {
  const supabase = createClient();
  
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];

  const { data: memberships } = await supabase
    .from('band_members')
    .select('band_id')
    .eq('user_id', user.id);

  if (!memberships || memberships.length === 0) return [];

  const bandIds = memberships.map(m => m.band_id);
  
  const { data: bands } = await supabase
    .from('bands')
    .select('*')
    .in('id', bandIds);

  return (bands || []) as Band[];
}