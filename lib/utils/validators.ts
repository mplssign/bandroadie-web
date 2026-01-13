import { z } from 'zod';

export const emailSchema = z.string().email('Invalid email address');

export const profileSchema = z.object({
  first_name: z.string().min(1, 'First name is required'),
  last_name: z.string().min(1, 'Last name is required'),
  phone: z.string().regex(/^\(\d{3}\) \d{3}-\d{4}$/, 'Invalid phone format'),
  address: z.string().min(1, 'Address is required'),
  zip: z.string().regex(/^\d{5}$/, 'Invalid ZIP code'),
  birthday: z.string().min(1, 'Birthday is required'),
  roles: z.array(z.string()).min(1, 'Select at least one role'),
});

export const bandSchema = z.object({
  name: z.string().min(1, 'Band name is required').transform(val => 
    val.split(' ').map(word => 
      word.charAt(0).toUpperCase() + word.slice(1).toLowerCase()
    ).join(' ')
  ),
  inviteEmails: z.array(z.string().email()).optional(),
});

export function validateEmail(email: string): boolean {
  try {
    emailSchema.parse(email);
    return true;
  } catch {
    return false;
  }
}

export function validateProfile(data: unknown): boolean {
  try {
    profileSchema.parse(data);
    return true;
  } catch {
    return false;
  }
}
