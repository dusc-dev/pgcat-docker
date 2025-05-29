FROM ghcr.io/postgresml/pgcat:latest

# Install envsubst and sponge
RUN \
  apt-get update \
  && apt-get -y install gettext-base moreutils \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Defaults, as envsubst doesn't support default syntax
ENV PORT=5432
ENV CONNECT_TIMEOUT=5000
ENV HEALTHCHECK_TIMEOUT=1000
ENV HEALTHCHECK_DELAY=30000
ENV SHUTDOWN_TIMEOUT=10000
ENV BAN_TIME=60
ENV LOG_CLIENT_CONNECTIONS=false
ENV LOG_CLIENT_DISCONNECTIONS=false
ENV ADMIN_USERNAME=admin
ENV ADMIN_PASSWORD=admin
ENV POOL_MODE=transaction
ENV DEFAULT_ROLE=replica
ENV QUERY_PARSER_ENABLED=true
ENV QUERY_PARSER_READ_WRITE_SPLITTING=true
ENV PRIMARY_READS_ENABLED=true
ENV POOL_SIZE=9
ENV STATEMENT_TIMEOUT=0
ENV SERVERS="mydb_prod#db1.example.com:5432:primary;db2.example.com:5433:replica;db3.example.com:5434:replica"
ENV USERS="username1:password1#pool_size=5,statement_timeout=0;username2:password2#pool_size=6,statement_timeout=10"

COPY config.template.toml /etc/pgcat/config.template.toml
COPY entrypoint.sh /etc/pgcat/entrypoint.sh
RUN chmod +x /etc/pgcat/entrypoint.sh

ENTRYPOINT ["/etc/pgcat/entrypoint.sh"]
