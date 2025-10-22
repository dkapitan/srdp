# 3. Usage & Verification

Once you have completed the setup, you can verify that all services are running correctly by accessing them in your web browser.

### Accessing Services

Because we configured Traefik to run on port `8888` to avoid conflicts, you must include `:8888` in the URLs.

*   **Marimo Dashboard:**
    *   URL: [http://marimo.localhost:8888](http://marimo.localhost:8888)
    *   You should see an interactive dashboard with a slider.

*   **Quarto Static Site:**
    *   URL: [http://quarto.localhost:8888](http://quarto.localhost:8888)
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

*   **To view the logs of all running services:**
    ```bash
    docker-compose logs -f
    ```

*   **To view the logs of a specific service (e.g., marimo):**
    ```bash
    docker-compose logs -f marimo
    ```