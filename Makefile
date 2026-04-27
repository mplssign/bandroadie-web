# Load .env and export all variables
ifneq (,$(wildcard .env))
  include .env
  export
endif

# ── Helpers ─────────────────────────────────────────────────────────────────

DART_DEFINES := $(foreach var, \
  SUPABASE_URL SUPABASE_ANON_KEY, \
  --dart-define=$(var)=$($(var)))

# ── Run ──────────────────────────────────────────────────────────────────────

run-macos:
	flutter run -d macos $(DART_DEFINES)

run-ios:
	flutter run -d iPhone $(DART_DEFINES)

run-web:
	flutter run -d chrome $(DART_DEFINES)

# ── Build ────────────────────────────────────────────────────────────────────

build-macos:
	flutter build macos $(DART_DEFINES)

build-web:
	flutter build web $(DART_DEFINES)

# ── Misc ─────────────────────────────────────────────────────────────────────

analyze:
	flutter analyze

clean:
	flutter clean && flutter pub get

.PHONY: run-macos run-ios run-web build-macos build-web analyze clean
