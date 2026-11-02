<p align="center">
  <img src="docs/icon.png" width="160" alt="f/2.8 icon">
</p>

<h1 align="center">f/2.8</h1>

<p align="center"><b>Shallow depth of field for your Mac.</b><br>
A menu bar app that softly blurs everything except the window you're working in.</p>

<p align="center">
  <a href="https://github.com/karnaghan/f2.8/releases/latest/download/f2.8.dmg"><b>⬇ Download f2.8.dmg</b></a>
  &nbsp;·&nbsp; macOS 14 Sonoma or later &nbsp;·&nbsp; Apple silicon & Intel &nbsp;·&nbsp; free
</p>

---

Shoot a portrait wide open at f/2.8 and only your subject is sharp; the background melts away.
f/2.8 does the same for your desktop. The window you're using stays crisp, and everything behind
it falls out of focus, so notifications, other chats and the twelve open tabs stop pulling at
your attention.

There are a few paid apps that do this. f/2.8 started as a weekend project to see how far a free
one could go, and ended up with most of what they offer, plus a couple of extras.

## Install

1. **[Download f2.8.dmg](https://github.com/karnaghan/f2.8/releases/latest/download/f2.8.dmg)** and open it.
2. Drag **f/2.8** onto the **Applications** folder.
3. Open it from Applications. The first time, macOS will stop it — see below.

### "Apple could not verify f/2.8…"

f/2.8 isn't signed with a paid Apple developer certificate, so macOS blocks it the first time.
This is a one-time step:

1. Double-click f/2.8. When the warning appears, click **Done**.
2. Open **System Settings → Privacy & Security** and scroll down to Security.
3. Next to *"f2.8 was blocked to protect your Mac"*, click **Open Anyway**, then enter your
   password.

After that it opens normally. If you'd rather use Terminal, this does the same thing:

```bash
xattr -dr com.apple.quarantine /Applications/f2.8.app
```

### Where is it?

f/2.8 shows an aperture icon in the Dock and in the menu bar. Click the Dock icon for settings.
On a crowded menu bar, MacBooks with a notch sometimes hide the menu bar icon; the Dock icon is
always there. If you prefer a menu-bar-only app, turn off **Settings → Behavior → Show in Dock**.

## What it does

**Two looks**
- **Deep** — everything behind your window is blurred, edge to edge.
- **Ambient** — a softer blur that falls off gradually around your window.

**Make it yours**
- Blur strength, tint (follows light/dark mode, or pick any colour), window dimming, film grain
  and a black-and-white **Monochrome** mode.
- **Reveal effects** when you switch windows: **Fade**, where the window you leave melts into the
  blur, or **Focus Pull**, where the background racks in and out of focus like a lens.

**Control it without thinking**
- **Shake the cursor** to toggle focus on or off.
- **Hold ⇧ and shake** to peek at everything for as long as you hold Shift.
- System-wide shortcuts:

  | Shortcut | Action |
  |---|---|
  | ⌃⌥⌘F | Toggle f/2.8 |
  | ⌃⌥⌘M | Switch between Deep and Ambient |
  | ⌃⌥⌘E | Ignore the app in front |
  | ⌃⌥⌘C | Show the floating control dot |

**Fits how you work**
- **Ignore apps** — f/2.8 steps aside while they're in front (handy for Finder).
- **App groups** — pair two apps, say your editor and its docs, and both stay sharp together.
- **App-wide focus** — keep every window of the current app sharp, not just the top one.
- **Multiple displays** — *Per screen* keeps the window you used last on each display sharp;
  *Global* keeps only your focused window sharp.
- **Stage Manager** — optionally blurs the thumbnail strip too.
- **Auto-hide the menu bar & Dock** while focus is on; your own settings come back when it's off.
- Launch at login.

## Privacy

f/2.8 has no analytics and never connects to the internet. It needs no Accessibility, Screen
Recording or Input Monitoring permission. The only prompt you might see is macOS asking whether
f/2.8 may control System Events, and only if you turn on auto-hide for the menu bar and Dock.

## How it works

Each display gets a borderless, click-through overlay window. About twenty times a second
f/2.8 reads the window list. That needs no permissions, because window IDs, owners and positions
are public. It then decides which windows should stay sharp and slides the overlay directly
beneath them in the window stack. Everything above the overlay stays sharp; everything below is
blurred live by macOS's own compositor. No screenshots are taken and no pixels are captured.

The blur is an `NSVisualEffectView` whose backdrop filters are swapped for a tunable Gaussian
blur and saturation, which is how blur strength and Monochrome work. If a future macOS changes
that, f/2.8 falls back to the window server's built-in background blur instead of breaking.
Ambient mode and the reveal transitions use a small alpha mask rendered on the CPU.

```
Sources/
  F28Core/       pure logic, no AppKit, unit tested
    FocusResolver   which window each display's overlay sits under
    ShakeDetector   cursor-shake recognition
    MaskRenderer    Ambient and transition masks
  F28/
    Engine/      overlay windows, blur tuning, window list, menu bar/Dock hiding
    Input/       global shortcuts and the shake monitor
    UI/          menu bar, Dock menu, floating dot, toasts, SwiftUI settings
  F28SelfTest/   39 checks
scripts/
  build.sh       swiftc-only build → build/f2.8.app (universal; runs the tests)
  make-dmg.sh    packages build/f2.8.dmg
  make-icon.swift  draws the aperture icon and writes AppIcon.icns
```

## Build from source

You need macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is
not required.

```bash
git clone https://github.com/karnaghan/f2.8.git
cd f2.8
make install      # builds, tests, copies to ~/Applications and launches
```

Other targets: `make run` (launch from `build/`), `make dmg` (package a disk image),
`make diagnose` (check the blur engine on your Mac) and `make clean`.

### Troubleshooting

`make diagnose`, or `~/Applications/f2.8.app/Contents/MacOS/F28 --diagnose`, prints which blur
engine is active, whether macOS lets f/2.8 sit beneath other apps' windows, and how focus
resolves right now. For a live log of focus changes:

```bash
F28_LOG=1 ~/Applications/f2.8.app/Contents/MacOS/F28
```

If a shortcut does nothing, another app already owns that key combination.
