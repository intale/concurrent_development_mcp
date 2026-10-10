# syntax=docker/dockerfile:1
# check=error=true

# Production image; deploy with bin/deploy-production (see README.md).
# Node is a build dependency only, never a production service or runtime.
ARG RUBY_IMAGE=ruby:4.0.6-slim@sha256:58479f164d5947f852da27a4436c89bb986a811f959c40552bc7f6ccaabcc9c9
ARG NODE_IMAGE=node:24-bookworm-slim@sha256:d6aa754f16b3197301076f047b5def2f02ea1dbbc2ca920407d46d7ec7f87b20

FROM ${NODE_IMAGE} AS frontend
WORKDIR /app/ui
COPY ui/package.json ui/yarn.lock ui/.yarnrc.yml ./
RUN corepack enable && yarn install --immutable
COPY ui/ ./
COPY app/graphql/schema.graphql /app/app/graphql/schema.graphql
RUN yarn build

FROM ${RUBY_IMAGE} AS base
WORKDIR /app

# Match the PostgreSQL 18 server. These are client tools only; all database
# connections go through PgBouncer.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates curl libjemalloc2 && \
    install -d /usr/share/postgresql-common/pgdg && \
    curl --fail --silent --show-error https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc && \
    . /etc/os-release && \
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y postgresql-client-18 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists/*

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

FROM base AS build
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf "${BUNDLE_PATH}"/ruby/*/cache && \
    bundle exec bootsnap precompile -j 1 --gemfile

# Explicit sources keep arbitrary host data directories, credentials, tests,
# recovery archives, and local build caches out of the runtime image.
COPY Rakefile config.ru .ruby-version ./
COPY app/ ./app/
COPY bin/ ./bin/
COPY config/ ./config/
COPY lib/ ./lib/
COPY db/migrate/ ./db/migrate/
COPY db/cache_schema.rb db/queue_schema.rb db/structure.sql db/seeds.rb ./db/
COPY public/ ./public/
RUN mkdir -p tmp/pids log storage && \
    bundle exec bootsnap precompile -j 1 app/ lib/

FROM base AS production
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
COPY --chown=rails:rails --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=rails:rails --from=build /app /app
COPY --chown=rails:rails --from=frontend /app/public/ui /app/public/ui
USER 1000:1000

ENTRYPOINT ["/app/bin/docker-entrypoint"]
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
