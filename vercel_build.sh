#!/usr/bin/env bash
# Build do Flutter Web na Vercel (a Vercel não traz o Flutter instalado).
set -e

if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 flutter
fi
export PATH="$PWD/flutter/bin:$PATH"

flutter config --enable-web
flutter pub get
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
