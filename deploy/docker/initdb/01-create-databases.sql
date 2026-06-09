-- Create service databases and roles for the SRDP platform.
-- This script runs once when the PostgreSQL data directory is first initialised.

-- Zitadel
CREATE USER zitadel WITH PASSWORD 'zitadel_pw';
CREATE DATABASE zitadel OWNER zitadel;

-- Dagster
CREATE USER dagster WITH PASSWORD 'dagster_pw';
CREATE DATABASE dagster OWNER dagster;
