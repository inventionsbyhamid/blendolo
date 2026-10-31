# The image bin/ci-remote runs bin/ci in (script/ci/run builds it): Ruby, the headers the gems build against, libvips
# for image variants, and Debian's Chromium with its driver for system tests. Gems live in a volume, not in the image.

ARG RUBY_VERSION=3.4.12
FROM docker.io/library/ruby:$RUBY_VERSION-slim-bookworm

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential chromium chromium-driver curl fonts-dejavu-core git \
      libffi-dev libgmp-dev libpq-dev libssl-dev libvips42 libyaml-dev pkg-config zlib1g-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV LANG="C.UTF-8"
WORKDIR /app
