-- Basic read-only checks for a restored PostgreSQL database.
--
-- Run this file separately against each restored database, for example:
--
-- psql -X -v ON_ERROR_STOP=1 \
--   -d ragdb_restore \
--   -f verification/verification.sql
--
-- psql -X -v ON_ERROR_STOP=1 \
--   -d n8n_db_restore \
--   -f verification/verification.sql

\set ON_ERROR_STOP on
\pset pager off

SELECT current_database() AS database_name;

SELECT
    extname AS extension,
    extversion AS version
FROM pg_extension
ORDER BY extname;

SELECT
    count(*) AS application_tables
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema');

SELECT
    tableowner AS owner,
    count(*) AS tables
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
GROUP BY tableowner
ORDER BY tableowner;

SELECT
    count(*) AS constraints,
    count(*) FILTER (WHERE NOT convalidated) AS unvalidated
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace;

SELECT
    count(*) AS indexes,
    count(*) FILTER (
        WHERE NOT index_data.indisvalid
           OR NOT index_data.indisready
    ) AS invalid
FROM pg_index AS index_data
JOIN pg_class AS index_class
    ON index_class.oid = index_data.indexrelid
JOIN pg_namespace AS schema_data
    ON schema_data.oid = index_class.relnamespace
WHERE schema_data.nspname = 'public';
