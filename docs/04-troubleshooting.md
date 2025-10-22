# 4. Troubleshooting

This section covers common issues you might encounter and how to solve them.

### Issue: `marimo.localhost` shows an "Apache Default Page" or "It Works!"

*   **Symptom:** You see a default web server page instead of the Marimo app.
*   **Cause:** Another web server (like Apache or Nginx) is running directly on your host machine and is using port 80. (For example, the backend for Docker Desktop does this.)
*   **Solution 1 (Recommended):** Change the port used by Traefik. In `docker-compose.yml`, change the `traefik` service's ports from `- "80:80"` to `- "8888:80"`. You will then need to access services at `http://marimo.localhost:8888`.
*   **Solution 2:** Find and stop the conflicting service. On Linux/WSL, you can check with `sudo lsof -i :80` and stop it with `sudo systemctl stop apache2`.

### Issue: The `quarto` container fails to build with `"/app/_site": not found`

*   **Symptom:** `docker-compose build` fails with an error during the `COPY --from=builder` step.
*   **Cause:** Quarto did not generate its output into an `_site` directory.
*   **Solution:** Ensure your `apps/quarto` directory is a proper Quarto project by including a `_quarto.yml` file. Then, use the command `RUN quarto render .` in your Dockerfile to render the entire project, which will correctly create the `_site` output directory.