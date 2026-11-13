# Install X1605VA Assistant

Install the latest published X1605VA Assistant directly from Terminal.

> **Deprecated:** This utility is kept for existing installations. Review the
> [project documentation](../README.md) before installing it on a new setup.

## Install from Terminal

Paste this command as your regular macOS user:

```sh
xcode-select -p >/dev/null 2>&1 || { xcode-select --install; until xcode-select -p >/dev/null 2>&1; do sleep 5; done; }; assistant_installer="$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/samuelnotfound/Asus-X1605VA-Hackintosh/main/install-assistant.sh)" && /bin/bash -c "$assistant_installer"
```

If Apple's Command Line Tools are not installed, macOS shows an install
prompt. Click **Install**; the command continues automatically once setup
finishes. The installer builds the latest published source, including its
artwork, and installs the app in `/Applications`. Rerun it for updates.

Click **Accessibility: Not Granted** in the menu-bar popup to open System
Settings. Remove any old entry, reopen the popup, and drag the app icon into
the Accessibility list. Turn on permission for the new entry. The app starts
at login after setup.

To remove the app, use **⋯ → Uninstall…**. See the
[project guide](../README.md) for keyboard shortcuts and hardware
requirements.
