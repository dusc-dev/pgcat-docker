# pgcat-docker
A pgcat Docker image configurable through environment variables.

# Environment Variables

| Name | Default Value |
|---|---|
| PORT | 5432 |
| CONNECT_TIMEOUT | 5000 |
| HEALTHCHECK_TIMEOUT | 1000 |
| HEALTHCHECK_DELAY | 30000 |
| SHUTDOWN_TIMEOUT | 10000 |
| BAN_TIME | 60 |
| LOG_CLIENT_CONNECTIONS | false |
| LOG_CLIENT_DISCONNECTIONS | false |
| ADMIN_USERNAME | admin |
| ADMIN_PASSWORD | admin |
| POOL_MODE | transaction |
| DEFAULT_ROLE | replica |
| QUERY_PARSER_ENABLED | true |
| QUERY_PARSER_READ_WRITE_SPLITTING | true |
| PRIMARY_READS_ENABLED | true |
| SERVERS | "mydb_prod#db1.example.com:5432:primary;db2.example.com:5433:replica;db3.example.com:5434:replica" |
| USERS | "username1:password1#pool_size=5,statement_timeout=0;username2:password2#pool_size=6,statement_timeout=10" |
