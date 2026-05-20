# Onshape → Bambu Studio

One-click "Send to Bambu" button inside Onshape. Pick which parts of the
current Part Studio you want to print, and they're exported as `.3mf` or `.stl` files
and loaded into Bambu Studio.

No more re-exporting, naming files, or hunting through your Downloads folder
every time you tweak a design.

![demo placeholder — add a screenshot or GIF here]

## How it works

Onshape is a cloud CAD tool; Bambu Studio is a desktop app. A browser button
can't directly hand a file to a desktop program, so this project has two
pieces that bridge them:

1. **A small Python service** that runs on `localhost:7777`. It talks to
   the Onshape REST API to list and export parts, then launches Bambu Studio
   with the resulting files.
2. **A Tampermonkey userscript** that adds a "Send to Bambu" button
   to every Onshape document page. When you click it, it calls the local
   service.

The service is bound to `127.0.0.1` only and CORS-locked to
`https://cad.onshape.com`, so nothing on the network can reach it.

## Requirements

- Windows 10/11 (the installer is PowerShell; the Python code is
  cross-platform but the autostart/launch flow is Windows-only for now)
- [Python 3.10+](https://www.python.org/downloads/) on PATH
- [Bambu Studio](https://bambulab.com/en/download/studio)
- [Tampermonkey](https://www.tampermonkey.net/) (or any compatible
  userscript manager) in your browser
- An Onshape account, plus a free API key pair (instructions below)

## Quick start

### 1. Get an Onshape API key

1. Sign in at [dev-portal.onshape.com](https://dev-portal.onshape.com).
2. Go to **API keys** → **Create new API key**.
3. Grant it at least **OAuth2Read** scope (read documents). Read/write are
   both fine.
4. Copy the **Access key** and **Secret key** — you'll paste them in the
   installer. The secret is shown only once.

### 2. Clone and install

```powershell
git clone https://github.com/<you>/onshape-bambu.git
cd onshape-bambu
.\install.ps1
```

The installer will:

- Verify Python 3.10+ is available
- Create a venv at `server\.venv` and install dependencies
- Prompt you for your Onshape access key + secret (secret is masked)
- Auto-detect your Bambu Studio install path
- Write `config.json` and attempt to lock its ACL to your Windows user
  (best-effort; harmless if it can't)
- Run a smoke test against the Onshape API
- Offer to install the bridge to your Startup folder (auto-launch on login)
- Start the bridge immediately

If the smoke test fails, the installer tells you so. You can re-run it any
time to update credentials.

### 3. Install the userscript

1. Install [Tampermonkey](https://www.tampermonkey.net/).
2. Open `userscript/onshape-bambu.user.js` in this repo, copy the entire
   contents.
3. Click the Tampermonkey extension icon → **Create a new script** → paste
   over the template → **Ctrl+S** to save.

### 4. Use it

1. Open any Part Studio at `cad.onshape.com`.
2. A green **Send to Bambu** button appears in the bottom-right corner.
   You can drag it anywhere on the page — its position is remembered.
3. Click it → check the parts you want → **Export & Open**.
4. Bambu Studio launches with the parts loaded.

## Iteration workflow

The big win is iterating on a print. Once you've sliced a part once:

1. Edit your model in Onshape.
2. Click **Send to Bambu** again. The same filename gets overwritten on disk.
3. In Bambu Studio: **File → Reload from disk**. Your supports, plate
   position, and slicing settings are preserved — only the geometry updates.

For this to feel best, enable **Preferences → General → Single Instance**
in Bambu Studio so the helper doesn't try to spawn a second copy.

Exported files live at `%USERPROFILE%\OnshapeExports\<DocName>__<ElementName>\`.

## Configuration

`config.json` (created by the installer):

| Field | What it does |
|---|---|
| `onshape_access_key` | Your Onshape API access key |
| `onshape_secret_key` | Your Onshape API secret key |
| `onshape_base_url` | Onshape host (default `https://cad.onshape.com`) |
| `bambu_studio_path` | Full path to `bambu-studio.exe` |
| `export_dir` | Where exports land (empty = `~/OnshapeExports`) |
| `export_format` | `"3MF"` (default) or `"STL"` |
| `port` | Local port the bridge listens on (default 7777) |

See [`config.example.json`](config.example.json) for the template.

If you change the port, also update the `BRIDGE` constant at the top of
`userscript/onshape-bambu.user.js`.

## Managing the bridge

**Is it running?** Open `http://127.0.0.1:7777/health` in your browser.

**Logs**: `server\bridge.log` — overwritten on each launch.

**Restart**: Task Manager → kill `python.exe`, then re-login (autostart picks
it up) or double-click `server\start-bridge.vbs`.

**Disable autostart**: `Win+R` → `shell:startup` → delete
`OnshapeBambuBridge.vbs`.

## Project layout

```
onshape-bambu/
├─ install.ps1              # Interactive installer
├─ config.example.json      # Template — copy to config.json (or use installer)
├─ .gitignore
├─ LICENSE                  # MIT
├─ README.md
├─ server/
│  ├─ main.py               # FastAPI bridge service
│  ├─ smoke_test.py         # Auth check used by install.ps1
│  ├─ requirements.txt
│  ├─ start-bridge.bat      # Runs the service and writes a log
│  └─ start-bridge.vbs      # Hidden-window launcher for the .bat (portable)
└─ userscript/
   └─ onshape-bambu.user.js # Tampermonkey button + modal
```

## Security notes

- `config.json` is gitignored and the installer tries to restrict its ACL to
  your Windows user (via `icacls`). On Windows the file also inherits your
  user-profile-adjacent directory permissions, so other users on the same
  machine cannot read it by default.
- The bridge listens on `127.0.0.1` only and accepts CORS only from
  `https://cad.onshape.com`. It is **not** exposed to your network.
- Any program already running on your machine can call the bridge
  (it has no auth). On a personal computer that's a non-issue; on a shared
  machine, consider adding a shared-secret header. PRs welcome.
- The Onshape secret key is stored in plaintext on disk. If you suspect it
  leaked, rotate it at [dev-portal.onshape.com](https://dev-portal.onshape.com).

## Troubleshooting

**"Could not reach bridge" in the userscript modal**
The Python service isn't running. Check `http://127.0.0.1:7777/health`
in your browser. If that fails, see `server\bridge.log`.

**"Unauthenticated API request" (401) from Onshape**
The Onshape API key didn't load. Re-run `install.ps1` and re-enter keys.

**"Bambu Studio not found"**
Edit `bambu_studio_path` in `config.json` to point at your real
`bambu-studio.exe`.

**Bambu Studio opens a new project instead of adding to my current plate**
Enable **Single Instance** in Bambu Studio preferences. With it on, new
launches route the file to the existing window. Whether it then adds to the
current plate vs. opens as a new project depends on Bambu Studio's version —
the **Reload from disk** workflow above sidesteps this entirely.

**3MF export fails but STL works**
Try setting `"export_format": "STL"` in `config.json` as a workaround, then
file an issue with the error from `bridge.log`.

## Why not just use a slash/keyboard shortcut in Onshape?

Onshape doesn't expose desktop integration hooks — the closest built-in
option is **File → Download**, which still routes through your browser's
download folder. The userscript + local bridge is the most reliable way to
skip the Downloads folder roundtrip without writing a full Onshape App Store
integration.

## License

MIT. See [LICENSE](LICENSE).

## Acknowledgments

Built for Bambu Studio iteration speed. Onshape's
[public REST API](https://onshape-public.github.io/docs/) makes the cloud
side possible.
