# 6. Troubleshooting

This section covers common issues you might encounter and how to solve them.

### Issue: `marimo.local.dev` shows an "Apache Default Page" or "It Works!"

*   **Symptom:** You see a default web server page instead of the Marimo app.
*   **Cause:** Another web server (like Apache or Nginx) is running directly on your host machine and is using port 80 or 443.
*   **Solution 1 (Recommended):** Stop the conflicting service. On Linux/WSL, you can check with `sudo lsof -i :80` and stop it with `sudo systemctl stop apache2`.
*   **Solution 2:** Change the ports used by Traefik in `docker-compose.yml` if you cannot stop the conflicting service.

### Issue: The `quarto` container fails to build with `"/app/_site": not found`

*   **Symptom:** `docker-compose build` fails with an error during the `COPY --from=builder` step.
*   **Cause:** Quarto did not generate its output into an `_site` directory.
*   **Solution:** Ensure your `apps/quarto` directory is a proper Quarto project by including a `_quarto.yml` file. Then, use the command `RUN quarto render .` in your Dockerfile to render the entire project, which will correctly create the `_site` output directory.

### Issue: Zitadel data lost after restart

*   **Symptom:** Your Zitadel project and apps are missing after restarting the containers.
*   **Cause:** You ran `docker compose down -v`, which removes all persistent volumes.
*   **Solution:** Only use `docker compose down` to stop the containers. Do **not** use the `-v` flag unless you intend to reset all data.