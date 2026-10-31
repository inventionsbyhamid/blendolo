# The dev container's image: the Rails dev container base with the Ruby in .ruby-version. The features in
# devcontainer.json add libvips and the Postgres client.
ARG RUBY_VERSION=3.4.12
FROM ghcr.io/rails/devcontainer/images/ruby:$RUBY_VERSION

# The server listens on every address of the container, so the forwarded port reaches it.
ENV BINDING="0.0.0.0"
