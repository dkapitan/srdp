# OSS Tool References

This document holds references to the sources used in the creation of this OSS tool.

## SSO and Identity Management

*   **[Self-hosting SSO with Traefik (Part 1): Keycloak](https://joeeey.com/blog/selfhosting-sso-with-traefik-keycloak-part-1/)**
    *   This blog post provides a comprehensive guide on setting up a self-hosted Single Sign-On (SSO) solution using Keycloak with Traefik as the reverse proxy. The main takeway way the setup for the oauth2 proxy and securing services.

*   **[Configure Zitadel with Traefik | ZITADEL Docs](https://zitadel.com/docs/self-hosting/manage/reverseproxy/traefik)**
    *   This official documentation from ZITADEL explains how to configure Zitadel with Traefik as a reverse proxy. It offers practical examples using Docker Compose and provides configurations for different TLS modes, including "TLS mode external" where Traefik terminates TLS, and "TLS mode enabled" for end-to-end encryption. We used the "TLS mode enabled" option.

## Reverse Proxy and Configuration

*   **[Setup Traefik Proxy in Docker Standalone - Traefik](https://doc.traefik.io/traefik/setup/docker/)**
    *   The official Traefik documentation provides a detailed walkthrough for installing and configuring Traefik Proxy within a Docker container using Docker Compose. It covers enabling the Docker provider, exposing HTTP and HTTPS entrypoints, redirecting HTTP to HTTPS, and deploying a sample application.

*   **[Overview | OAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview)**
    *   This documentation provides a complete overview of the configuration options for OAuth2 Proxy. It details how to configure the proxy via command-line options. The page lists all available flags for general provider options, cookie settings, header options, logging, and more.