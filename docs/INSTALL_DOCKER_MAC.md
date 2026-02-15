# Install Docker on macOS

You’re on **macOS** (darwin). Use one of the options below. After installation, **start Docker Desktop** at least once so the `docker` and `docker compose` commands work in the terminal.

---

## Don’t have Homebrew?

Install Homebrew first (one command in Terminal). You’ll need **Xcode Command Line Tools**; if they’re missing, the script will prompt you to install them.

**Install Homebrew:**
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

- Follow the prompts (it may ask for your Mac password).
- When it finishes, it will show two lines to add to your PATH (e.g. for Apple Silicon: `echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile` and `eval "$(/opt/homebrew/bin/brew shellenv)"`). Run those so `brew` works in new terminals.
- Check: `brew --version`

Then use **Option A** below to install Docker with Homebrew.

---

## Option A: Homebrew (recommended if you use Homebrew)

1. **Install Docker Desktop (cask):**
   ```bash
   brew install --cask docker
   ```
   Use **`--cask`** so you get Docker Desktop (the full app), not just the CLI.

2. **Open Docker Desktop**  
   From **Applications** or run:
   ```bash
   open -a Docker
   ```
   Wait until the whale icon appears in the menu bar and Docker says it’s running.

3. **Check that CLI works:**
   ```bash
   docker --version
   docker compose version
   ```

4. **Run the microservices:**
   ```bash
   cd "/Users/ranjansoni/Documents/AI Projects/AI Agent"
   docker compose up -d
   ./scripts/test-microservices.sh
   ```

---

## Option B: Direct download (no Homebrew)

1. **Download**  
   Go to: [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/)  
   - **Apple Silicon (M1/M2/M3):** choose “Mac with Apple chip”  
   - **Intel:** choose “Mac with Intel chip”

2. **Install**  
   - Open the downloaded `.dmg`  
   - Drag **Docker** into **Applications**

3. **First run**  
   - Open **Docker** from Applications (or Spotlight: ⌘+Space → “Docker”)  
   - Accept the terms and wait until Docker is running (whale icon in menu bar)

4. **Verify in terminal:**
   ```bash
   docker --version
   docker compose version
   ```

5. **Run the project:**
   ```bash
   cd "/Users/ranjansoni/Documents/AI Projects/AI Agent"
   docker compose up -d
   ./scripts/test-microservices.sh
   ```

---

## Notes

- **Docker Desktop** includes both `docker` and **Docker Compose v2** (`docker compose`). This project uses `docker compose` (with a space), not the old `docker-compose` (hyphen) command.
- If you use an older setup that only has `docker-compose` (hyphen), run:
  ```bash
  docker-compose up -d
  ```
  instead of `docker compose up -d`.
- **Licensing:** Docker Desktop is free for personal use, education, and small businesses (see [Docker’s page](https://www.docker.com/pricing/)).

---

## If something goes wrong

- **“docker: command not found”**  
  Start Docker Desktop from Applications and wait until it’s fully running, then try again in a **new** terminal window.

- **“Cannot connect to the Docker daemon”**  
  Docker Desktop isn’t running. Open the Docker app and wait for the menu bar icon to show it’s ready.

- **Permission denied when running the test script**  
  ```bash
  chmod +x scripts/test-microservices.sh
  ```
