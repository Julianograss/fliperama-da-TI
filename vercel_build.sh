
#!/usr/bin/env bash
set -e

echo "Iniciando build do Flutter Web..."

# Verifica as variáveis do Supabase
if [ -z "$SUPABASE_URL" ]; then
  echo "ERRO: SUPABASE_URL não configurada!"
  exit 1
fi

if [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "ERRO: SUPABASE_ANON_KEY não configurada!"
  exit 1
fi

# Baixa o Flutter
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git \
    -b stable --depth 1 flutter
fi

export PATH="$PWD/flutter/bin:$PATH"

# Configura Flutter Web
flutter config --enable-web

# Instala dependências
flutter pub get

# Compila o projeto
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

echo "Build concluído com sucesso!"
