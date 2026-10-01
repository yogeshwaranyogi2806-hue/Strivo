# Strivo - Flutter Web App Dockerfile
# Build stage
FROM ghcr.io/cirruslabs/flutter:stable AS builder

ARG SUPABASE_URL=""
ARG SUPABASE_ANON_KEY=""
ENV SUPABASE_URL=$SUPABASE_URL
ENV SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY

WORKDIR /app

# Copy dependency files first for better caching
COPY mobile/pubspec.yaml mobile/pubspec.lock ./mobile/
RUN cd mobile && flutter pub get

# Copy source code
COPY mobile/ ./mobile/

# Build web release
RUN cd mobile && flutter build web --release --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY

# Serve stage
FROM nginx:alpine

# Copy built web app
COPY --from=builder /app/mobile/build/web /usr/share/nginx/html

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
