# 5. Cloud Deployment (GCP)

This guide covers the entire process of deploying the application stack to Google Cloud Platform using OpenTofu. It includes provisioning the infrastructure, configuring the services, and verifying the deployment.

## Phase 1: Prerequisites & Initial Setup

Before deploying, ensure your local environment is configured and your project's variable file is prepared.

### System Prerequisites

You must have the following tools installed and configured on your local machine:

*   **OpenTofu:** Follow the [official installation guide](https://opentofu.org/docs/intro/install/).
*   **Google Cloud SDK (`gcloud`):** Follow the [official installation guide](https://cloud.google.com/sdk/docs/install).

Once installed, authenticate with Google Cloud by running the following command in your terminal:
```bash
gcloud auth application-default login
```

### Optional: Using a Custom Domain

While this guide uses a free `nip.io` domain for quick testing, you can easily use your own registered domain.

1.  **Get a Domain:** If you don't have one, purchase a domain from a registrar like Google Domains or Namecheap.

2.  **Create a DNS Record:** After you complete **Phase 2, Step A** of this guide and have your static IP address, go to your domain registrar's DNS management panel and create the following record:
    *   **Type:** `A`
    *   **Name / Host:** `*.srdp` (This is a wildcard record that will cover `auth.srdp.yourdomain.com`, `marimo.srdp.yourdomain.com`, etc.)
    *   **Value:** The static IP address you get from the `tofu apply` output.
    *   **TTL:** Set a low value (e.g., 300 seconds) for faster updates.

    > **Note:** It can take anywhere from a few minutes to an hour for DNS changes to propagate across the internet.

### Project Configuration (`tofu.tfvars`)

The deployment is driven by a variables file.

1.  Navigate to the OpenTofu directory for this project:
    ```bash
    cd path/to/your/project/opentofu/providers/gcp
    ```
2.  In this directory, you will find a template file. Make a copy of it and name it **`tofu.tfvars`**.

3.  Open your new `tofu.tfvars` file and fill in the values. For the first run, use a placeholder IP for the domain name.

    ```hcl
    gcp_project_id = "single-repo-data-platform"
    repo_url       = "https://github.com/dkapitan/srdp.git"
    acme_email     = "email@example.nl"
    domain_name    = "1.1.1.1.nip.io" # Placeholder for the first run

    # --- Secrets ---
    # Generate a long, random string (e.g., using `openssl rand -base64 32`)
    zitadel_masterkey  = "YOUR_ZITADEL_MASTERKEY_HERE"
    oidc_cookie_secret = "YOUR_OIDC_COOKIE_SECRET_HERE"

    # Use placeholders for now; we will get the real values later.
    oidc_client_id     = "placeholder-id"
    oidc_client_secret = "placeholder-secret"
    ```

## Phase 2: Infrastructure Provisioning (Two-Step Apply)

This is a two-step process because we first need to reserve a static IP address, and then use that IP to configure the final virtual machine.

### Step A: First Apply (Reserve IP)

1.  Initialize your OpenTofu project. This downloads the necessary cloud provider plugins.
    ```bash
    tofu init -upgrade
    ```
2.  Run the `apply` command to create the initial resources, including the static IP.
    ```bash
    tofu apply -var-file="tofu.tfvars"
    ```
    When prompted, review the plan and type `yes` to confirm.

3.  After the command completes, copy the **real static IP address** from the output.
    ```
    Outputs:

    instance_name = "srdp-main"
    static_ip_address = "34.90.31.51"  <-- COPY THIS VALUE
    ```
    > **Custom Domain User?** Now is the time to go to your DNS provider and create the `*.srdp` A record pointing to this IP.

### Step B: Second Apply (Deploy Final VM)

1.  Update your `tofu.tfvars` file. Replace the placeholder `domain_name` with your public domain.
    *   **For `nip.io`:** `domain_name = "34.90.31.51.nip.io"` (Use your copied IP)
    *   **For a Custom Domain:** `domain_name = "srdp.yourdomain.com"`

2.  Run the `apply` command a second time.
    ```bash
    tofu apply -var-file="tofu.tfvars"
    ```
    OpenTofu will plan to replace the VM. This is expected. Type `yes` to confirm.

3.  **Wait approximately 5-10 minutes** for the VM to boot and for the startup script to download and start all the containers.

## Phase 3: Application Configuration

The VM is running with a fresh Zitadel instance. This is a one-time manual setup to create the OIDC application and synchronize the secrets.

### Step A: Create the OIDC Application in Zitadel

1.  **Access the Cloud Zitadel UI:**
    *   URL: `https://auth.<your-public-domain>` (e.g., `https://auth.34.90.31.51.nip.io` or `https://auth.srdp.yourdomain.com`)

2.  **Log In as Administrator:**
    *   **Username:** `zitadel-admin@auth.<your-public-domain>`
    *   **Password:** `Password1!`

3.  **Create the OIDC Application:**
    *   Navigate to **Projects** and create a **New Project**.
    *   Inside the project, create a new **Application** of type **OIDC**.
    *   Give it a name (e.g., `Traefik Middleware`).
    *   For **Redirect URIs**, add an entry for each application you are protecting, using your public domain:
        *   `https://marimo.<your-public-domain>/oauth2/callback`
        *   `https://quarto.<your-public-domain>/oauth2/callback`
    *   Click **Continue** and then **Create**.

4.  **Copy the New Secrets:** On the success screen, copy the auto-generated **Client ID** and **Client Secret** to a temporary text file.

### Step B: Update the VM via SSH

1.  **Connect to the VM:**
    ```bash
    gcloud compute ssh srdp-main --zone "europe-west4-a"
    ```
2.  **Navigate to the Application Directory:**
    ```bash
    cd /opt/app/local/
    ```
3.  **Edit the `.env` File:**
    ```bash
    sudo nano .env
    ```
4.  **Update the Secrets:**
    *   Inside the `nano` editor, find the `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET` lines.
    *   Delete the old placeholder values and paste in the correct values you copied from the Zitadel UI.
    *   Save and exit: `Ctrl+X`, then `Y`, then `Enter`.

5.  **Restart the Application Services:** This command applies the new secrets by restarting the affected containers.
    ```bash
    sudo docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
    ```

## Phase 4: Verification

Your deployment is now complete and correctly configured.

### Accessing Cloud Services

Open a new **incognito/private browser window** to test the full authentication flow. Use the following URLs, replacing `<your-public-domain>` with your actual domain.

*   **Marimo Dashboard:**
    *   URL: `https://marimo.<your-public-domain>`
    *   You should be redirected to the Zitadel login page, and after authenticating, see the interactive dashboard.

*   **Quarto Static Site:**
    *   URL: `https://quarto.<your-public-domain>`
    *   You should have access immediately without needing to log in again (Single Sign-On).