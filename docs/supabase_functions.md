# Supabase Edge Functions

## Overview

Edge Functions are located in `supabase/functions/`. They handle external API integrations with token caching.

## Deployment

```bash
supabase functions deploy <function-name>
```

## Authentication

All Edge Functions validate the JWT from the `Authorization` header using Supabase's built-in auth.

---

> See `supabase/functions/` for individual function implementations.
