# Architecture

## Overview

BandRoadie is a cross-platform Flutter app (iOS, Android, macOS, Web) for band management. The backend is powered by Supabase (PostgreSQL + Auth + Edge Functions).

## Feature-First Structure

Code is organized by feature in `lib/features/`, not by layer. Each feature folder contains its own models, services, widgets, repository, controller, and screen.

## State Management

Riverpod `Notifier` + `NotifierProvider` pattern is used throughout.

## Band Isolation

All data is scoped to the active band via `activeBandProvider`.

---

> See `BAND_ROADIE_DOCUMENTATION.md` and `.github/copilot-instructions.md` for full architecture details.
