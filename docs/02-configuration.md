# 2. Local Configuration & Setup

This guide will walk you through the steps to get the Single Repo Data Platform (SRDP) running on your local machine.

### Step 1: Clone the Repository

First, clone this repository to a location of your choice on your computer.

Open your terminal, navigate to your development directory, and run:

```bash
git clone git@github.com:dkapitan/srdp.git # or git clone https://github.com/dkapitan/srdp.git
cd srdp/local
```

### Step 2: Configure Local Hostnames

To access the services using friendly names like `marimo.local.dev`, you need to edit your computer's `hosts` file. This file maps domain names to IP addresses. We will map our service domains to your local machine's IP, `127.0.0.1`.

**Why is this necessary?**
When you type `marimo.local.dev` into your browser, this file tells the browser to send the request to your own computer instead of trying to find a public website on the internet. Traefik, our proxy, will then receive this request and route it to the correct Docker container.

---

#### On macOS or Linux:

1.  Open a terminal.
2.  Run the following command to open the hosts file with `nano`, a simple text editor. You will be prompted for your password.
    ```bash
    sudo nano /etc/hosts
    ```

#### On Windows:

1.  Press the Windows key, type `Notepad`, right-click on it, and select **"Run as administrator"**.
2.  In Notepad, go to `File` > `Open`.
3.  Navigate to `c:\Windows\System32\Drivers\etc\hosts`.
4.  You may need to change the file type filter in the bottom-right corner from "Text Documents (*.txt)" to **"All files (*.*)"** to see the `hosts` file.

---

#### Add the Following Line:

Add this single line to the **bottom** of the `hosts` file.

```
127.0.0.1   marimo.local.dev quarto.local.dev auth.local.dev
```

Save the file and exit the editor. (In `nano`, press `Ctrl+X`, then `Y`, then `Enter`). **You may need to restart your machine in order for changes to take effect.**

### Step 2b: Generate Certificates

You should generate local development certificates using [mkcert](https://github.com/FiloSottile/mkcert):

```bash
mkcert -cert-file ./certs/selfsigned.crt -key-file ./certs/selfsigned.key "*.local.dev" "local.dev"
```

**Make sure to put these certificates under /local/certs. The easies way to accomplish this is to run the previous comppand inside the /local/ directory.**

### Step 3: Launch the Services

Now you are ready to start all the services. Navigate to the root of the project directory in your terminal and run:

```bash
docker-compose up --build -d
```

*   `--build`: This flag tells Docker Compose to build the application images (for Marimo and Quarto) from their `Dockerfile`s before starting the services. You should use this the first time you run the command or after you've made changes to the application code.
*   `-d`: This runs the containers in "detached" mode, meaning they will run in the background and your terminal will be free to use.

**Note:** The first time you run this, Zitadel will be initialized but the database will be empty. You can log in as an admin using:

- **Username:** `zitadel-admin@zitadel.auth.local.dev`
- **Password:** `Password1!`

After logging in, create a new project (e.g., "Protected Apps"). Then, create a new app with type **Web**, authentication method **Code**, and add the following redirect URIs:

- `https://marimo.local.dev/oauth2/callback`
- `https://quarto.local.dev/oauth2/callback`

And post logout URIs:

- `https://marimo.local.dev`
- `https://quarto.local.dev`

When the project is created, Zitadel will display a client ID and secret. Copy these and set them in your `.env` file under `/local/`:

```
OIDC_CLIENT_ID=your-client-id
OIDC_CLIENT_SECRET=your-client-secret
```

After updating the `.env` file, run:

```bash
docker compose up --force-recreate
```

OR

```bash
docker compose down
docker compose up --build
```

**Important:** Do **not** run `docker compose down -v`, as the `-v` option will destroy existing data, including the project and app you created in Zitadel.

**Congratulations! The local environment should now be up and running.** Proceed to the next section, **Usage & Verification**, to confirm that everything is working correctly.