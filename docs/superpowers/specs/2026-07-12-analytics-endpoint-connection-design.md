# Analytics Endpoint Connection Fix

## Problem

Bot heartbeats reach `https://www.nexbot.cc/api/track`, but the API rejects Vercel's URL-encoded city header before calling Supabase. A live request returned HTTP 400 with `Invalid city`. The bot also sends an obsolete deletion request on shutdown even though analytics rows should be retained.

## Design

- Decode Vercel geo headers before validating and passing them to `upsert_bot`.
- Return HTTP 400 for malformed encoding or decoded city values outside the existing allowlist.
- Keep the existing heartbeat RPC so `upsert_bot` remains responsible for updating last-seen state.
- Stop sending a deletion request when the bot shuts down. Offline state is derived from the persisted last-seen timestamp.
- Do not add dependencies or change the database schema.

## Verification

- Add a focused route test for an encoded city such as `S%C3%A3o%20Paulo` and malformed encoding.
- Run the site tests, type check, and production build.
- After deployment, call the public endpoint and confirm an HTTP 200 response and the Supabase row's updated last-seen value.
