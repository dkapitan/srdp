# 3. Usage & Verification

Once you have completed the setup, you can verify that all services are running correctly by accessing them in your web browser.

### Accessing Services

Use the following URLs. You will be prompted to authenticate before accessing each service. You can use the admin credentials from [02-configuration.md](./02-configuration.md):

*   **Marimo Dashboard:**
    *   URL: [https://marimo.local.dev](https://marimo.local.dev)
    *   You should see an interactive dashboard with a slider.

*   **Quarto Static Site:**
    *   URL: [https://quarto.local.dev](https://quarto.local.dev)
    *   You should see a static HTML report titled "My Quarto Report".

*   **Traefik Dashboard (for debugging):**
    *   URL: [http://localhost:8080](http://localhost:8080)
    *   This provides a view of Traefik's configuration, including all detected routers and services. It is very useful for troubleshooting routing issues.

### Managing the Services

You can manage the containers using standard `docker-compose` commands:

*   **To build and start the services:**
    ```bash
    docker-compose up --build # Remove --build if no changes were made
    ```

*   **To stop the services:**
    ```bash
    docker-compose down
    ```

    **Do not use `docker-compose down -v` unless you want to destroy all persistent data, including your Zitadel configuration.**

*   **To view the logs of all running services:**
    ```bash
    docker-compose logs -f
    ```

*   **To view the logs of a specific service (e.g., marimo):**
    ```bash
    docker-compose logs -f marimo
    ```